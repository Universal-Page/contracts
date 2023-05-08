// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";
import {Module, MARKETPLACE_ROLE, OPERATOR_ROLE} from "../common/Module.sol";
import {ILSP8Listings, LSP8Listing} from "./ILSP8Listings.sol";

contract LSP8Listings is ILSP8Listings, Module {
    error InsufficientAuthorization(address account, bytes32 tokenId);
    error InvalidListingTime(uint256 time);
    error NotListed(uint256 id);
    error UnathorizedSeller(address account);
    error InactiveListing(uint256 id);
    error AlreadyListed(uint256 id);

    uint256 public totalListings;
    // id -> listing
    mapping(uint256 => LSP8Listing) private _listings;
    // hash(asset, tokenId) -> id
    mapping(bytes32 => uint256) private _listingIds;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_) external initializer {
        Module._initialize(newOwner_);
    }

    function isListed(uint256 id) public view override returns (bool) {
        return _listings[id].seller != address(0);
    }

    function isActiveListing(uint256 id) public view override returns (bool) {
        LSP8Listing memory listing = _listings[id];
        return isListed(id) && (block.timestamp >= listing.startTime)
            && ((listing.endTime == 0) || (block.timestamp < listing.endTime));
    }

    function getListing(uint256 id) public view override returns (LSP8Listing memory) {
        if (!isListed(id)) {
            revert NotListed(id);
        }
        return _listings[id];
    }

    function list(address asset, bytes32 tokenId, uint256 price, uint256 startTime, uint256 secondsUntilEndTime)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address seller = msg.sender;
        address owner = ILSP8IdentifiableDigitalAsset(asset).tokenOwnerOf(tokenId);
        bool isOperator = ILSP8IdentifiableDigitalAsset(asset).isOperatorFor(seller, tokenId);
        if (!isOperator && !hasRole(seller, MARKETPLACE_ROLE)) {
            revert InsufficientAuthorization(seller, tokenId);
        }
        totalListings += 1;
        uint256 id = totalListings;
        // verify existing possible listing
        {
            bytes32 existingKey = _listingKey(asset, tokenId);
            uint256 existingId = _listingIds[existingKey];
            LSP8Listing memory existingListing = _listings[existingId];
            if (existingListing.seller != address(0)) {
                if (
                    existingListing.seller == seller
                        && ((existingListing.endTime == 0) || (block.timestamp < existingListing.endTime))
                ) {
                    revert AlreadyListed(existingId);
                }
                delete _listings[existingId];
                emit Delisted(existingId, asset);
            }
            _listingIds[existingKey] = id;
        }
        uint256 endTime = 0;
        if (secondsUntilEndTime > 0) {
            endTime = startTime + secondsUntilEndTime;
        }
        _listings[id] = LSP8Listing({
            seller: seller,
            asset: asset,
            owner: owner,
            tokenId: tokenId,
            price: price,
            startTime: startTime,
            endTime: endTime
        });
        emit Listed(id, asset, seller, owner, tokenId, price, startTime, endTime);
        return id;
    }

    function update(uint256 id, uint256 price, uint256 startTime, uint256 secondsUntilEndTime)
        external
        override
        whenNotPaused
        nonReentrant
    {
        LSP8Listing memory listing = getListing(id);
        if (msg.sender != listing.seller) {
            revert UnathorizedSeller(msg.sender);
        }
        bool isOperator = ILSP8IdentifiableDigitalAsset(listing.asset).isOperatorFor(listing.seller, listing.tokenId);
        if (!isOperator) {
            revert InsufficientAuthorization(listing.seller, listing.tokenId);
        }
        uint256 endTime = 0;
        if (secondsUntilEndTime > 0) {
            endTime = startTime + secondsUntilEndTime;
        }
        _listings[id] = LSP8Listing({
            seller: listing.seller,
            asset: listing.asset,
            owner: listing.owner,
            tokenId: listing.tokenId,
            price: price,
            startTime: startTime,
            endTime: endTime
        });
        emit Updated(id, listing.asset, price, startTime, endTime);
    }

    function delist(uint256 id) external override whenNotPaused nonReentrant {
        LSP8Listing memory listing = getListing(id);
        if (msg.sender != listing.seller && !hasRole(msg.sender, OPERATOR_ROLE)) {
            revert UnathorizedSeller(msg.sender);
        }
        delete _listings[id];
        delete _listingIds[_listingKey(listing.asset, listing.tokenId)];
        emit Delisted(id, listing.asset);
    }

    function unlist(uint256 id) external override whenNotPaused nonReentrant onlyMarketplace {
        LSP8Listing memory listing = getListing(id);
        if (!isActiveListing(id)) {
            revert InactiveListing(id);
        }
        delete _listings[id];
        delete _listingIds[_listingKey(listing.asset, listing.tokenId)];
        emit Unlisted(id, listing.asset);
    }

    function _listingKey(address asset, bytes32 tokenId) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(asset, tokenId));
    }
}
