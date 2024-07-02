// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {Base} from "../common/Base.sol";
import {IParticipant} from "../IParticipant.sol";
import {ILSP7Listings, LSP7Listing} from "./ILSP7Listings.sol";
import {ILSP7Orders, LSP7Order} from "./ILSP7Orders.sol";

uint8 constant SALE_KIND_MASK = 0xF;
uint8 constant SALE_KIND_SPOT = 0;
uint8 constant SALE_KIND_OFFER = 1;
uint8 constant SALE_KIND_ORDER = 2;

contract LSP7Marketplace is Base {
    event Sold(
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        uint256 itemCount,
        uint256 totalPaid,
        uint256 totalFee,
        uint256 totalRoyalties,
        bytes data
    );
    event RoyaltiesPaidOut(
        address indexed asset, uint256 itemCount, uint256 totalPaid, address indexed recipient, uint256 amount
    );

    error InsufficientFunds(uint256 totalPrice, uint256 totalPaid);
    error FeesExceedTotalPaid(uint256 totalPaid, uint256 feesAmount, uint256 royaltiesTotalAmount);
    error Unpaid(address account, uint256 amount);
    error UnathorizedSeller(address account);

    ILSP7Listings public listings;
    ILSP7Orders public orders;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address newOwner_,
        address beneficiary_,
        ILSP7Listings listings_,
        ILSP7Orders orders_,
        IParticipant participant_
    ) external initializer {
        Base._initialize(newOwner_, beneficiary_, participant_);
        listings = listings_;
        orders = orders_;
    }

    function buy(uint256 listingId, uint256 itemCount, address recipient) external payable whenNotPaused nonReentrant {
        LSP7Listing memory listing = listings.getListing(listingId);
        if (listing.itemPrice * itemCount != msg.value) {
            revert InsufficientFunds(listing.itemPrice * itemCount, msg.value);
        }
        listings.deduct(listingId, itemCount);
        _executeSale(
            listing.asset, itemCount, listing.owner, recipient, msg.value, abi.encodePacked(SALE_KIND_SPOT, listingId)
        );
    }

    function fillOrder(uint256 orderId, uint256 itemCount) external whenNotPaused nonReentrant {
        address seller = msg.sender;
        LSP7Order memory order = orders.getOrder(orderId);
        orders.fill(orderId, seller, itemCount);
        _executeSale(
            order.asset,
            itemCount,
            seller,
            order.buyer,
            order.itemPrice * itemCount,
            abi.encodePacked(SALE_KIND_ORDER, order.id)
        );
    }

    function _executeSale(
        address asset,
        uint256 itemCount,
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
        emit Sold(asset, seller, buyer, itemCount, totalPaid, feeAmount, royaltiesTotalAmount, data);
        uint256 royaltiesRecipientsCount = royaltiesRecipients.length;
        for (uint256 i = 0; i < royaltiesRecipientsCount; i++) {
            if (royaltiesAmounts[i] > 0) {
                (bool royaltiesPaid,) = royaltiesRecipients[i].call{value: royaltiesAmounts[i]}("");
                if (!royaltiesPaid) {
                    revert Unpaid(royaltiesRecipients[i], royaltiesAmounts[i]);
                }
                emit RoyaltiesPaidOut(asset, itemCount, totalPaid, royaltiesRecipients[i], royaltiesAmounts[i]);
            }
        }
        uint256 sellerAmount = totalPaid - feeAmount - royaltiesTotalAmount;
        (bool paid,) = seller.call{value: sellerAmount}("");
        if (!paid) {
            revert Unpaid(seller, sellerAmount);
        }
        ILSP7DigitalAsset(asset).transfer(seller, buyer, itemCount, false, data);
    }

    // Deprecated events
    event Sale(
        uint256 indexed listingId,
        address indexed asset,
        uint256 itemCount,
        address indexed seller,
        address buyer,
        uint256 totalPaid
    );
    event RoyaltiesPaid(
        uint256 indexed listingId, address indexed asset, uint256 itemCount, address indexed recipient, uint256 amount
    );
    event FeePaid(uint256 indexed listingId, address indexed asset, uint256 itemCount, uint256 amount);
}
