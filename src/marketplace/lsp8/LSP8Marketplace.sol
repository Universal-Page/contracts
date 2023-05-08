// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";
import {Base} from "../common/Base.sol";
import {Royalties} from "../../common/Royalties.sol";
import {IPageNameMarketplace, PendingSale} from "../../page/IPageNameMarketplace.sol";
import {IParticipant} from "../IParticipant.sol";
import {ILSP8Listings, LSP8Listing} from "./ILSP8Listings.sol";
import {ILSP8Offers, LSP8Offer} from "./ILSP8Offers.sol";
import {ILSP8Auctions, LSP8Auction, LSP8Bid} from "./ILSP8Auctions.sol";

contract LSP8Marketplace is IPageNameMarketplace, Base {
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

    error InsufficientFunds(uint256 totalPrice, uint256 totalPaid);
    error FeesExceedTotalPaid(uint256 totalPaid, uint256 feesAmount, uint256 royaltiesTotalAmount);
    error Unpaid(uint256 listingId, address account, uint256 amount);
    error UnathorizedSeller(address account);
    error NoPendingSale();
    error Auctioned(uint256 listingId);

    ILSP8Listings public listings;
    ILSP8Offers public offers;
    ILSP8Auctions public auctions;
    PendingSale private _pendingSale;
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
        ILSP8Auctions auctions_,
        IParticipant participant_
    ) external initializer {
        require(address(listings_) != address(0));
        require(address(offers_) != address(0));
        require(address(auctions_) != address(0));
        Base._initialize(newOwner_, beneficiary_, participant_);
        listings = ILSP8Listings(listings_);
        offers = ILSP8Offers(offers_);
        auctions = ILSP8Auctions(auctions_);
    }

    function pendingSale() external view returns (PendingSale memory) {
        if (_pendingSale.asset == address(0)) {
            revert NoPendingSale();
        }
        return _pendingSale;
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
        _executeSale(listingId, listing.asset, listing.tokenId, listing.owner, recipient, msg.value);
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
        _executeSale(listingId, listing.asset, listing.tokenId, listing.owner, buyer, offer.price);
    }

    function acceptHighestBid(uint256 listingId) external whenNotPaused nonReentrant {
        LSP8Auction memory auction = auctions.getAuction(listingId);
        if (auction.seller != msg.sender) {
            revert UnathorizedSeller(msg.sender);
        }
        LSP8Bid memory bid = auctions.getHighestBid(listingId);
        LSP8Listing memory listing = listings.getListing(listingId);
        auctions.settle(listingId);
        _executeSale(listingId, listing.asset, listing.tokenId, listing.owner, bid.buyer, bid.totalPaid);
    }

    function _executeSale(
        uint256 listingId,
        address asset,
        bytes32 tokenId,
        address seller,
        address buyer,
        uint256 totalPaid
    ) private {
        _pendingSale = PendingSale({asset: asset, tokenId: tokenId, seller: seller, buyer: buyer, totalPaid: totalPaid});
        (uint256 royaltiesTotalAmount, address[] memory royaltiesRecipients, uint256[] memory royaltiesAmounts) =
            _calculateRoyalties(asset, totalPaid);
        uint256 feeAmount = _calculateFeeWithDiscount(seller, totalPaid);
        if (feeAmount + royaltiesTotalAmount > totalPaid) {
            revert FeesExceedTotalPaid(totalPaid, feeAmount, royaltiesTotalAmount);
        }
        if (totalPaid <= lastPurchasePrice(seller, asset, tokenId) && !Royalties.royaltiesPaymentEnforced(asset)) {
            (bool paid,) = seller.call{value: totalPaid - feeAmount}("");
            if (!paid) {
                revert Unpaid(listingId, seller, totalPaid - feeAmount);
            }
        } else {
            uint256 royaltiesRecipientsCount = royaltiesRecipients.length;
            for (uint256 i = 0; i < royaltiesRecipientsCount;) {
                if (royaltiesAmounts[i] > 0) {
                    (bool royaltiesPaid,) = royaltiesRecipients[i].call{value: royaltiesAmounts[i]}("");
                    if (!royaltiesPaid) {
                        revert Unpaid(listingId, royaltiesRecipients[i], royaltiesAmounts[i]);
                    }
                    emit RoyaltiesPaid(listingId, asset, tokenId, royaltiesRecipients[i], royaltiesAmounts[i]);
                }
                unchecked {
                    i++;
                }
            }
            uint256 sellerAmount = totalPaid - feeAmount - royaltiesTotalAmount;
            (bool paid,) = seller.call{value: sellerAmount}("");
            if (!paid) {
                revert Unpaid(listingId, seller, sellerAmount);
            }
        }
        if (feeAmount > 0) {
            emit FeePaid(listingId, asset, tokenId, feeAmount);
        }
        ILSP8IdentifiableDigitalAsset(asset).transfer(seller, buyer, tokenId, false, "");
        delete _pendingSale;
        _lastPurchasePrice[buyer][asset][tokenId] = totalPaid;
        emit Sale(listingId, asset, tokenId, seller, buyer, totalPaid);
    }
}
