// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_TOKEN_TYPE_NFT
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {Module, OPERATOR_ROLE} from "../common/Module.sol";
import {ILSP7Listings, LSP7Listing} from "./ILSP7Listings.sol";

contract LSP7Listings is ILSP7Listings, Module {
    error InvalidListingZeroItems();
    error InsufficientAuthorization(address account, uint256 minimumRequired, uint256 authorizedAllowance);
    error InvalidListingTime(uint256 time);
    error NotListed(uint256 id);
    error UnathorizedSeller(address account);
    error InactiveListing(uint256 id);
    error InvalidDeduction(uint256 available, uint256 deducted);
    error InvalidListingAmount(uint256 total, uint256 authorizedAllowance);
    error InvalidListingType(address asset, uint256 lsp4TokenType, bool isNonDivisible);

    uint256 public totalListings;
    mapping(uint256 => LSP7Listing) private _listings;
    mapping(bytes32 => uint256) private _listedAmount;

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
        LSP7Listing memory listing = _listings[id];
        return isListed(id) && (block.timestamp >= listing.startTime)
            && ((listing.endTime == 0) || (block.timestamp < listing.endTime));
    }

    function getListing(uint256 id) public view override returns (LSP7Listing memory) {
        if (!isListed(id)) {
            revert NotListed(id);
        }
        return _listings[id];
    }

    function list(
        address asset,
        address owner,
        uint256 itemCount,
        uint256 itemPrice,
        uint256 startTime,
        uint256 secondsUntilEndTime
    ) external override whenNotPaused nonReentrant returns (uint256) {
        if (itemCount == 0) {
            revert InvalidListingZeroItems();
        }
        // verify that the asset is a non-divisible NFT
        {
            uint256 tokenType = uint256(bytes32(ILSP7DigitalAsset(asset).getData(_LSP4_TOKEN_TYPE_KEY)));
            bool divisible = ILSP7DigitalAsset(asset).decimals() != 0;
            if (tokenType != _LSP4_TOKEN_TYPE_NFT || divisible) {
                revert InvalidListingType(asset, tokenType, !divisible);
            }
        }
        address seller = msg.sender;
        uint256 allowance = ILSP7DigitalAsset(asset).authorizedAmountFor(seller, owner);
        if (allowance < itemCount) {
            revert InsufficientAuthorization(seller, itemCount, allowance);
        }
        // verify that the listing is valid
        {
            bytes32 key = _listingKey(asset, owner);
            uint256 listedAmount = _listedAmount[key] + itemCount;
            if (listedAmount > allowance) {
                revert InvalidListingAmount(listedAmount, allowance);
            }
            _listedAmount[key] = listedAmount;
        }
        totalListings += 1;
        uint256 id = totalListings;
        uint256 endTime = 0;
        if (secondsUntilEndTime > 0) {
            endTime = startTime + secondsUntilEndTime;
        }
        _listings[id] = LSP7Listing({
            seller: seller,
            asset: asset,
            owner: owner,
            itemCount: itemCount,
            itemPrice: itemPrice,
            startTime: startTime,
            endTime: endTime
        });
        emit Listed(id, asset, seller, owner, itemCount, itemPrice, startTime, endTime);
        return id;
    }

    function update(uint256 id, uint256 itemCount, uint256 itemPrice, uint256 startTime, uint256 secondsUntilEndTime)
        external
        override
        whenNotPaused
        nonReentrant
    {
        LSP7Listing memory listing = getListing(id);
        if (msg.sender != listing.seller) {
            revert UnathorizedSeller(msg.sender);
        }
        uint256 allowance = ILSP7DigitalAsset(listing.asset).authorizedAmountFor(listing.seller, listing.owner);
        if (allowance < itemCount) {
            revert InsufficientAuthorization(listing.seller, itemCount, allowance);
        }
        bytes32 key = _listingKey(listing.asset, listing.owner);
        uint256 listedAmount = _listedAmount[key];
        if (listedAmount >= listing.itemCount) {
            listedAmount -= listing.itemCount;
        }
        listedAmount += itemCount;
        if (listedAmount > allowance) {
            revert InvalidListingAmount(listedAmount, allowance);
        }
        _listedAmount[key] = listedAmount;
        uint256 endTime = 0;
        if (secondsUntilEndTime > 0) {
            endTime = startTime + secondsUntilEndTime;
        }
        _listings[id] = LSP7Listing({
            seller: listing.seller,
            asset: listing.asset,
            owner: listing.owner,
            itemCount: itemCount,
            itemPrice: itemPrice,
            startTime: startTime,
            endTime: endTime
        });
        emit Updated(id, listing.asset, itemCount, itemPrice, startTime, endTime);
    }

    function delist(uint256 id) external override whenNotPaused nonReentrant {
        LSP7Listing memory listing = getListing(id);
        if (msg.sender != listing.seller && !hasRole(msg.sender, OPERATOR_ROLE)) {
            revert UnathorizedSeller(msg.sender);
        }
        bytes32 key = _listingKey(listing.asset, listing.owner);
        uint256 listedAmount = _listedAmount[key];
        if (listedAmount >= listing.itemCount) {
            _listedAmount[key] -= listing.itemCount;
        }
        delete _listings[id];
        emit Delisted(id, listing.asset);
    }

    function deduct(uint256 id, uint256 itemCount) external override whenNotPaused nonReentrant onlyMarketplace {
        LSP7Listing memory listing = getListing(id);
        if (!isActiveListing(id)) {
            revert InactiveListing(id);
        }
        if (itemCount == 0 || itemCount > listing.itemCount) {
            revert InvalidDeduction(listing.itemCount, itemCount);
        }
        bytes32 key = _listingKey(listing.asset, listing.owner);
        uint256 listedAmount = _listedAmount[key];
        if (listedAmount >= itemCount) {
            _listedAmount[key] -= itemCount;
        }
        _listings[id].itemCount -= itemCount;
        emit Deducted(id, listing.asset, itemCount);
        if (_listings[id].itemCount == 0) {
            delete _listings[id];
            emit Unlisted(id, listing.asset);
        }
    }

    function _listingKey(address asset, address seller) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(asset, seller));
    }
}
