// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {Module} from "../common/Module.sol";
import {ILSP7Listings, LSP7Listing} from "./ILSP7Listings.sol";
import {ILSP7Offers, LSP7Offer} from "./ILSP7Offers.sol";

contract LSP7Offers is ILSP7Offers, Module {
    error NotPlaced(uint256 listingId, address buyer);
    error InvalidOfferZeroItems();
    error InvalidOfferDuration(uint256 secondsUntilExpiration);
    error InvalidOfferTotalPrice(uint256 totalPrice);
    error InactiveListing(uint256 listingId);
    error InactiveOffer(uint256 listingId, address buyer);
    error Unpaid(uint256 listingId, address buyer, uint256 amount);
    error InsufficientListingItemCount(uint256 listingId, uint256 listedCount, uint256 offeredCount);

    ILSP7Listings public listings;
    // listing id -> buyer -> offer
    mapping(uint256 => mapping(address => LSP7Offer)) private _offers;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_, ILSP7Listings listings_) external initializer {
        Module._initialize(newOwner_);
        listings = listings_;
    }

    function isPlacedOffer(uint256 listingId, address buyer) public view override returns (bool) {
        return _offers[listingId][buyer].expirationTime != 0;
    }

    function isActiveOffer(uint256 listingId, address buyer) public view override returns (bool) {
        return _offers[listingId][buyer].expirationTime > block.timestamp;
    }

    function getOffer(uint256 listingId, address buyer) public view override returns (LSP7Offer memory) {
        if (!isPlacedOffer(listingId, buyer)) {
            revert NotPlaced(listingId, buyer);
        }
        return _offers[listingId][buyer];
    }

    function place(uint256 listingId, uint256 itemCount, uint256 totalPrice, uint256 secondsUntilExpiration)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        if (!listings.isActiveListing(listingId)) {
            revert InactiveListing(listingId);
        }
        if (itemCount == 0) {
            revert InvalidOfferZeroItems();
        }
        if ((secondsUntilExpiration < 1 hours) || (secondsUntilExpiration > 28 days)) {
            revert InvalidOfferDuration(secondsUntilExpiration);
        }
        LSP7Offer memory lastOffer = _offers[listingId][msg.sender];
        uint256 actualTotalPrice = msg.value + lastOffer.totalPrice;
        if (actualTotalPrice != totalPrice) {
            revert InvalidOfferTotalPrice(totalPrice);
        }
        uint256 expirationTime = block.timestamp + secondsUntilExpiration;
        _offers[listingId][msg.sender] =
            LSP7Offer({itemCount: itemCount, totalPrice: actualTotalPrice, expirationTime: expirationTime});
        emit Placed(listingId, msg.sender, itemCount, actualTotalPrice, expirationTime);
    }

    function cancel(uint256 listingId) external override whenNotPaused nonReentrant {
        LSP7Offer memory offer = getOffer(listingId, msg.sender);
        delete _offers[listingId][msg.sender];
        (bool success,) = msg.sender.call{value: offer.totalPrice}("");
        if (!success) {
            revert Unpaid(listingId, msg.sender, offer.totalPrice);
        }
        emit Canceled(listingId, msg.sender, offer.itemCount, offer.totalPrice);
    }

    function accept(uint256 listingId, address buyer) external override whenNotPaused nonReentrant onlyMarketplace {
        LSP7Listing memory listing = listings.getListing(listingId);
        if (!listings.isActiveListing(listingId)) {
            revert InactiveListing(listingId);
        }
        LSP7Offer memory offer = getOffer(listingId, buyer);
        if (!isActiveOffer(listingId, buyer)) {
            revert InactiveOffer(listingId, buyer);
        }
        if (offer.itemCount > listing.itemCount) {
            revert InsufficientListingItemCount(listingId, listing.itemCount, offer.itemCount);
        }
        delete _offers[listingId][buyer];
        (bool success,) = msg.sender.call{value: offer.totalPrice}("");
        if (!success) {
            revert Unpaid(listingId, msg.sender, offer.totalPrice);
        }
        emit Accepted(listingId, buyer, offer.itemCount, offer.totalPrice);
    }
}
