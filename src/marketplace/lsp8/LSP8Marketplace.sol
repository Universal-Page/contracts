// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";
import {Base} from "../common/Base.sol";
import {Royalties} from "../../common/Royalties.sol";
import {IParticipant} from "../IParticipant.sol";
import {ILSP8Listings, LSP8Listing} from "./ILSP8Listings.sol";
import {ILSP8Offers, LSP8Offer} from "./ILSP8Offers.sol";
import {ILSP8Orders, LSP8Order} from "./ILSP8Orders.sol";
import {ILSP8Auctions, LSP8Auction, LSP8Bid} from "./ILSP8Auctions.sol";

uint8 constant SALE_KIND_MASK = 0xF;
uint8 constant SALE_KIND_SPOT = 0;
uint8 constant SALE_KIND_OFFER = 1;
uint8 constant SALE_KIND_ORDER = 2;

contract LSP8Marketplace is Base {
    event Sold(
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        bytes32 tokenId,
        uint256 totalPaid,
        uint256 totalFee,
        uint256 totalRoyalties,
        bytes data
    );
    event RoyalitiesPaidOut(
        address indexed asset, bytes32 tokenId, uint256 totalPaid, address indexed recipient, uint256 amount
    );

    error InsufficientFunds(uint256 totalPrice, uint256 totalPaid);
    error FeesExceedTotalPaid(uint256 totalPaid, uint256 feesAmount, uint256 royaltiesTotalAmount);
    error Unpaid(address account, uint256 amount);
    error UnathorizedSeller(address account);
    error Auctioned(uint256 listingId);
    error Disabled(string message);

    ILSP8Listings public listings;
    ILSP8Offers public offers;
    ILSP8Auctions public auctions;
    ILSP8Orders public orders;
    uint256 private _unused_storage_slot_1;
    uint256 private _unused_storage_slot_2;
    uint256 private _unused_storage_slot_3;
    uint256 private _unused_storage_slot_4;
    // profile -> asset -> token id -> price
    mapping(address => mapping(address => mapping(bytes32 => uint256))) private _lastPurchasePrice;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address newOwner_,
        address beneficiary_,
        ILSP8Listings listings_,
        ILSP8Offers offers_,
        ILSP8Orders orders_,
        ILSP8Auctions auctions_,
        IParticipant participant_
    ) external initializer {
        require(address(listings_) != address(0));
        require(address(offers_) != address(0));
        require(address(auctions_) != address(0));
        require(address(orders_) != address(0));
        Base._initialize(newOwner_, beneficiary_, participant_);
        listings = ILSP8Listings(listings_);
        offers = ILSP8Offers(offers_);
        orders = ILSP8Orders(orders_);
        auctions = ILSP8Auctions(auctions_);
    }

    function setOrders(ILSP8Orders orders_) external onlyOwner {
        require(address(orders_) != address(0));
        orders = orders_;
    }

    function lastPurchasePrice(address buyer, address asset, bytes32 tokenId) public view returns (uint256) {
        return _lastPurchasePrice[buyer][asset][tokenId];
    }

    function buy(uint256 listingId, address recipient) external payable whenNotPaused nonReentrant {
        if (auctions.isIssued(listingId)) {
            revert Auctioned(listingId);
        }
        LSP8Listing memory listing = listings.getListing(listingId);
        if (listing.price != msg.value) {
            revert InsufficientFunds(listing.price, msg.value);
        }
        listings.unlist(listingId);
        _executeSale(
            listing.asset,
            listing.tokenId,
            listing.owner,
            recipient,
            msg.value,
            abi.encodePacked(SALE_KIND_SPOT, listingId)
        );
    }

    function acceptOffer(uint256 listingId, address buyer) external whenNotPaused nonReentrant {
        if (auctions.isIssued(listingId)) {
            revert Auctioned(listingId);
        }
        LSP8Listing memory listing = listings.getListing(listingId);
        if (listing.seller != msg.sender) {
            revert UnathorizedSeller(msg.sender);
        }
        LSP8Offer memory offer = offers.getOffer(listingId, buyer);
        offers.accept(listingId, buyer);
        listings.unlist(listingId);
        _executeSale(
            listing.asset,
            listing.tokenId,
            listing.owner,
            buyer,
            offer.price,
            abi.encodePacked(SALE_KIND_OFFER, listingId)
        );
    }

    function acceptHighestBid(uint256 listingId) external whenNotPaused {
        LSP8Auction memory auction = auctions.getAuction(listingId);
        if (auction.seller != msg.sender) {
            revert UnathorizedSeller(msg.sender);
        }
        // LSP8Bid memory bid = auctions.getHighestBid(listingId);
        // LSP8Listing memory listing = listings.getListing(listingId);
        auctions.settle(listingId);
        revert Disabled("Auctions are deprecated");
    }

    function fillOrder(uint256 orderId, bytes32[] calldata tokenIds) external whenNotPaused nonReentrant {
        address seller = msg.sender;
        LSP8Order memory order = orders.getOrder(orderId);
        orders.fill(orderId, seller, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _executeSale(
                order.asset,
                tokenIds[i],
                seller,
                order.buyer,
                order.tokenPrice,
                abi.encodePacked(SALE_KIND_ORDER, order.id)
            );
        }
    }

    function _executeSale(
        address asset,
        bytes32 tokenId,
        address seller,
        address buyer,
        uint256 totalPaid,
        bytes memory data
    ) private {
        (uint256 royaltiesTotalAmount, address[] memory royaltiesRecipients, uint256[] memory royaltiesAmounts) =
            _calculateRoyalties(asset, totalPaid);
        uint256 feeAmount = _calculateFeeWithDiscount(seller, totalPaid);
        if (feeAmount + royaltiesTotalAmount > totalPaid) {
            revert FeesExceedTotalPaid(totalPaid, feeAmount, royaltiesTotalAmount);
        }
        if (totalPaid <= lastPurchasePrice(seller, asset, tokenId) && !Royalties.royaltiesPaymentEnforced(asset)) {
            emit Sold(asset, seller, buyer, tokenId, totalPaid, feeAmount, 0, data);
            (bool paid,) = seller.call{value: totalPaid - feeAmount}("");
            if (!paid) {
                revert Unpaid(seller, totalPaid - feeAmount);
            }
        } else {
            emit Sold(asset, seller, buyer, tokenId, totalPaid, feeAmount, royaltiesTotalAmount, data);
            uint256 royaltiesRecipientsCount = royaltiesRecipients.length;
            for (uint256 i = 0; i < royaltiesRecipientsCount; i++) {
                if (royaltiesAmounts[i] > 0) {
                    (bool royaltiesPaid,) = royaltiesRecipients[i].call{value: royaltiesAmounts[i]}("");
                    if (!royaltiesPaid) {
                        revert Unpaid(royaltiesRecipients[i], royaltiesAmounts[i]);
                    }
                    emit RoyalitiesPaidOut(asset, tokenId, totalPaid, royaltiesRecipients[i], royaltiesAmounts[i]);
                }
            }
            uint256 sellerAmount = totalPaid - feeAmount - royaltiesTotalAmount;
            (bool paid,) = seller.call{value: sellerAmount}("");
            if (!paid) {
                revert Unpaid(seller, sellerAmount);
            }
        }
        ILSP8IdentifiableDigitalAsset(asset).transfer(seller, buyer, tokenId, false, data);
        _lastPurchasePrice[buyer][asset][tokenId] = totalPaid;
    }

    // Deprecated events
    event Sale(
        uint256 indexed listingId,
        address indexed asset,
        bytes32 tokenId,
        address indexed seller,
        address buyer,
        uint256 totalPaid
    );
    event RoyaltiesPaid(
        uint256 indexed listingId, address indexed asset, bytes32 tokenId, address indexed recipient, uint256 amount
    );
    event FeePaid(uint256 indexed listingId, address indexed asset, bytes32 tokenId, uint256 amount);
}
