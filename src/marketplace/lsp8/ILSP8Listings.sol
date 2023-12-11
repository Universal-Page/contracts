// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

struct LSP8Listing {
    address seller;
    address asset;
    address owner;
    bytes32 tokenId;
    uint256 price;
    uint256 startTime;
    uint256 endTime;
}

interface ILSP8Listings {
    /// an asset has been listed with id by an owner
    event Listed(
        uint256 indexed id,
        address indexed asset,
        address seller,
        address indexed owner,
        bytes32 tokenId,
        uint256 price,
        uint256 startTime,
        uint256 endTime
    );
    /// a listing for asset has been updated with id
    event Updated(uint256 indexed id, address indexed asset, uint256 price, uint256 startTime, uint256 endTime);
    /// a listing has been explicitly delisted
    event Delisted(uint256 indexed id, address indexed asset);
    /// a listing has been unlisted due being sold
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
    function getListing(uint256 id) external view returns (LSP8Listing memory);

    /// lists new asset
    /// @param asset asset to list
    /// @param tokenId token id to list
    /// @param price price
    /// @param startTime time in seconds to make listing available
    /// @param secondsUntilEndTime seconds for how long listing is available or zero to make indefinite
    /// @return listingId id of a listed item
    function list(address asset, bytes32 tokenId, uint256 price, uint256 startTime, uint256 secondsUntilEndTime)
        external
        returns (uint256);

    /// updates listed asset
    /// @param id listing id
    /// @param price price
    /// @param startTime time in seconds to make listing available
    /// @param secondsUntilEndTime seconds for how long listing is available or zero to make it indefinite
    function update(uint256 id, uint256 price, uint256 startTime, uint256 secondsUntilEndTime) external;

    /// delists an asset by a seller
    function delist(uint256 id) external;

    /// unlists an asset when sold
    function unlist(uint256 id) external;
}
