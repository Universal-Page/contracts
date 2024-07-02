// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";
import {Module} from "../common/Module.sol";
import {ILSP8Listings, LSP8Listing} from "./ILSP8Listings.sol";
import {ILSP8Offers, LSP8Offer} from "./ILSP8Offers.sol";

uint256 constant CANCELATION_COOLDOWN = 1 hours;

contract LSP8Offers is ILSP8Offers, Module {
    error NotPlaced(uint256 listingId, address buyer);
    error InvalidOfferDuration(uint256 secondsUntilExpiration);
    error InvalidOfferTotalPrice(uint256 totalPrice);
    error InactiveListing(uint256 listingId);
    error InactiveOffer(uint256 listingId, address buyer);
    error Unpaid(uint256 listingId, address buyer, uint256 amount);
    error RecentlyCanceled(uint256 listingId, address buyer, uint256 cooldownTimestamp);

    ILSP8Listings public listings;
    // listing id -> buyer -> offer
    mapping(uint256 => mapping(address => LSP8Offer)) private _offers;
    mapping(uint256 listingId => mapping(address buyer => uint256 cooldownTimestamp)) private _cancellationCooldown;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_, ILSP8Listings listings_) external initializer {
        Module._initialize(newOwner_);
        listings = listings_;
    }

    function isPlacedOffer(uint256 listingId, address buyer) public view override returns (bool) {
        return _offers[listingId][buyer].expirationTime != 0;
    }

    function isActiveOffer(uint256 listingId, address buyer) public view override returns (bool) {
        return _offers[listingId][buyer].expirationTime > block.timestamp;
    }

    function getOffer(uint256 listingId, address buyer) public view override returns (LSP8Offer memory) {
        if (!isPlacedOffer(listingId, buyer)) {
            revert NotPlaced(listingId, buyer);
        }
        return _offers[listingId][buyer];
    }

    function place(uint256 listingId, uint256 totalPrice, uint256 secondsUntilExpiration)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        LSP8Listing memory listing = listings.getListing(listingId);
        if (!listings.isActiveListing(listingId)) {
            revert InactiveListing(listingId);
        }
        if ((secondsUntilExpiration < 1 hours) || (secondsUntilExpiration > 28 days)) {
            revert InvalidOfferDuration(secondsUntilExpiration);
        }
        LSP8Offer memory lastOffer = _offers[listingId][msg.sender];
        uint256 actualTotalPrice = msg.value + lastOffer.price;
        if (actualTotalPrice != totalPrice) {
            revert InvalidOfferTotalPrice(totalPrice);
        }
        uint256 expirationTime = block.timestamp + secondsUntilExpiration;
        _offers[listingId][msg.sender] = LSP8Offer({price: actualTotalPrice, expirationTime: expirationTime});
        emit Placed(listingId, msg.sender, listing.tokenId, actualTotalPrice, expirationTime);
    }

    function cancel(uint256 listingId) external override whenNotPaused nonReentrant {
        address buyer = msg.sender;
        LSP8Offer memory offer = getOffer(listingId, buyer);
        delete _offers[listingId][buyer];
        _cancellationCooldown[listingId][buyer] = block.timestamp;
        (bool success,) = buyer.call{value: offer.price}("");
        if (!success) {
            revert Unpaid(listingId, buyer, offer.price);
        }
        emit Canceled(listingId, buyer, offer.price);
    }

    function accept(uint256 listingId, address buyer) external override whenNotPaused nonReentrant onlyMarketplace {
        if (!listings.isActiveListing(listingId)) {
            revert InactiveListing(listingId);
        }
        LSP8Offer memory offer = getOffer(listingId, buyer);
        if (!isActiveOffer(listingId, buyer)) {
            revert InactiveOffer(listingId, buyer);
        }
        delete _offers[listingId][buyer];
        // verify cooldown period if the offer was recently canceled
        uint256 cooldownTimestamp = _cancellationCooldown[listingId][buyer];
        if ((cooldownTimestamp > 0) && (cooldownTimestamp + CANCELATION_COOLDOWN > block.timestamp)) {
            revert RecentlyCanceled(listingId, buyer, cooldownTimestamp + CANCELATION_COOLDOWN);
        }
        (bool success,) = msg.sender.call{value: offer.price}("");
        if (!success) {
            revert Unpaid(listingId, msg.sender, offer.price);
        }
        emit Accepted(listingId, buyer, offer.price);
    }
}
