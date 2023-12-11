// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

struct LSP7Listing {
    address seller;
    address asset;
    address owner;
    uint256 itemCount;
    uint256 itemPrice;
    uint256 startTime;
    uint256 endTime;
}

interface ILSP7Listings {
    /// an asset has been listed with id by an owner
    event Listed(
        uint256 indexed id,
        address indexed asset,
        address seller,
        address indexed owner,
        uint256 itemCount,
        uint256 itemPrice,
        uint256 startTime,
        uint256 endTime
    );
    /// a listing for asset has been updated with id
    event Updated(
        uint256 indexed id,
        address indexed asset,
        uint256 itemCount,
        uint256 itemPrice,
        uint256 startTime,
        uint256 endTime
    );
    /// a listing has been explicitly delisted
    event Delisted(uint256 indexed id, address indexed asset);
    /// a listing has been partially deducted (e.g. sold)
    event Deducted(uint256 indexed id, address indexed asset, uint256 itemCount);
    /// a listing has been unlisted due deduction of all available items
    event Unlisted(uint256 indexed id, address indexed asset);

    /// total number of listings ever listed
    function totalListings() external view returns (uint256);

    /// confirms a listing with id is listed
    /// @param id listing id
    function isListed(uint256 id) external view returns (bool);

    /// confirms a listing with id is active
    /// @param id listing id
    function isActiveListing(uint256 id) external view returns (bool);

    /// retrieves a listing by an id or reverts if not listed
    /// @param id listing id
    function getListing(uint256 id) external view returns (LSP7Listing memory);

    /// lists new asset
    /// @param asset asset to list
    /// @param owner owner of asset
    /// @param itemCount number of items to list
    /// @param itemPrice price per item
    /// @param startTime time in seconds to make listing available
    /// @param secondsUntilEndTime seconds for how long listing is available or zero to make indefinite
    /// @return listingId id of a listed item
    function list(
        address asset,
        address owner,
        uint256 itemCount,
        uint256 itemPrice,
        uint256 startTime,
        uint256 secondsUntilEndTime
    ) external returns (uint256);

    /// updates listed asset
    /// @param id listing id
    /// @param itemCount number of items to list
    /// @param itemPrice price per item
    /// @param startTime time in seconds to make listing available
    /// @param secondsUntilEndTime seconds for how long listing is available or zero to make it indefinite
    function update(uint256 id, uint256 itemCount, uint256 itemPrice, uint256 startTime, uint256 secondsUntilEndTime)
        external;

    /// delists an asset by a seller
    function delist(uint256 id) external;

    /// deducts a number of items from a listing. When no more items are remained, unlists the listing.
    function deduct(uint256 id, uint256 itemCount) external;
}
