// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {Base} from "../common/Base.sol";
import {IParticipant} from "../IParticipant.sol";
import {ILSP7Listings, LSP7Listing} from "./ILSP7Listings.sol";
import {ILSP7Offers, LSP7Offer} from "./ILSP7Offers.sol";

contract LSP7Marketplace is Base {
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

    error InsufficientFunds(uint256 totalPrice, uint256 totalPaid);
    error FeesExceedTotalPaid(uint256 totalPaid, uint256 feesAmount, uint256 royaltiesTotalAmount);
    error Unpaid(uint256 listingId, address account, uint256 amount);
    error UnathorizedSeller(address account);

    ILSP7Listings public listings;
    ILSP7Offers public offers;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address newOwner_,
        address beneficiary_,
        ILSP7Listings listings_,
        ILSP7Offers offers_,
        IParticipant participant_
    ) external initializer {
        require(address(listings_) != address(0));
        require(address(offers_) != address(0));
        Base._initialize(newOwner_, beneficiary_, participant_);
        listings = listings_;
        offers = offers_;
    }

    function buy(uint256 listingId, uint256 itemCount, address recipient) external payable whenNotPaused nonReentrant {
        LSP7Listing memory listing = listings.getListing(listingId);
        if (listing.itemPrice * itemCount != msg.value) {
            revert InsufficientFunds(listing.itemPrice * itemCount, msg.value);
        }
        listings.deduct(listingId, itemCount);
        _executeSale(listingId, listing.asset, itemCount, listing.owner, recipient, msg.value);
    }

    function acceptOffer(uint256 listingId, address buyer) external whenNotPaused nonReentrant {
        LSP7Listing memory listing = listings.getListing(listingId);
        if (listing.seller != msg.sender) {
            revert UnathorizedSeller(msg.sender);
        }
        LSP7Offer memory offer = offers.getOffer(listingId, buyer);
        offers.accept(listingId, buyer);
        listings.deduct(listingId, offer.itemCount);
        _executeSale(listingId, listing.asset, offer.itemCount, listing.owner, buyer, offer.totalPrice);
    }

    function _executeSale(
        uint256 listingId,
        address asset,
        uint256 itemCount,
        address seller,
        address buyer,
        uint256 totalPaid
    ) private {
        (uint256 royaltiesTotalAmount, address[] memory royaltiesRecipients, uint256[] memory royaltiesAmounts) =
            _calculateRoyalties(asset, totalPaid);
        uint256 feeAmount = _calculateFeeWithDiscount(seller, totalPaid);
        if (feeAmount + royaltiesTotalAmount > totalPaid) {
            revert FeesExceedTotalPaid(totalPaid, feeAmount, royaltiesTotalAmount);
        }
        uint256 royaltiesRecipientsCount = royaltiesRecipients.length;
        for (uint256 i = 0; i < royaltiesRecipientsCount; i++) {
            if (royaltiesAmounts[i] > 0) {
                (bool royaltiesPaid,) = royaltiesRecipients[i].call{value: royaltiesAmounts[i]}("");
                if (!royaltiesPaid) {
                    revert Unpaid(listingId, royaltiesRecipients[i], royaltiesAmounts[i]);
                }
                emit RoyaltiesPaid(listingId, asset, itemCount, royaltiesRecipients[i], royaltiesAmounts[i]);
            }
        }
        uint256 sellerAmount = totalPaid - feeAmount - royaltiesTotalAmount;
        (bool paid,) = seller.call{value: sellerAmount}("");
        if (!paid) {
            revert Unpaid(listingId, seller, sellerAmount);
        }
        if (feeAmount > 0) {
            emit FeePaid(listingId, asset, itemCount, feeAmount);
        }
        ILSP7DigitalAsset(asset).transfer(seller, buyer, itemCount, false, "");
        emit Sale(listingId, asset, itemCount, seller, buyer, totalPaid);
    }
}
