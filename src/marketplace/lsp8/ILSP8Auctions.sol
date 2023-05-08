// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

struct LSP8Auction {
    address seller;
    uint256 startPrice;
    uint256 startTime;
    uint256 endTime;
}

struct LSP8Bid {
    address buyer;
    uint256 totalPaid;
}

interface ILSP8Auctions {
    /// an asset has been auctioned
    event Issued(
        uint256 indexed listingId,
        address indexed seller,
        address indexed owner,
        bytes32 tokenId,
        uint256 startPrice,
        uint256 startTime,
        uint256 endTime
    );
    /// an auction was canceled and an item is unlisted
    event Canceled(uint256 indexed listingId, address indexed seller, address indexed owner, bytes32 tokenId);
    /// an auction has been settled with a seller accepting a highest bid
    event Settled(
        uint256 indexed listingId,
        address seller,
        address indexed owner,
        bytes32 tokenId,
        address indexed buyer,
        uint256 totalPaid
    );
    /// a buyer placed new bid
    event Offered(
        uint256 indexed listingId,
        address seller,
        address indexed owner,
        bytes32 tokenId,
        address indexed buyer,
        uint256 totalPaid
    );
    /// a buyer retracted their bid
    event Retracted(uint256 indexed listingId, address indexed buyer, uint256 totalPaid);

    /// confirms an auction is issued
    /// @param listingId listing id
    function isIssued(uint256 listingId) external view returns (bool);

    /// confirms an auction is active
    /// @param listingId listing id
    function isActiveAuction(uint256 listingId) external view returns (bool);

    /// retrieves an auction by a listing id or reverts if not issued
    /// @param listingId listing id
    function getAuction(uint256 listingId) external view returns (LSP8Auction memory);

    /// issues an auction
    /// @param asset asset to auction
    /// @param tokenId token id to auction
    /// @param startPrice starting price or a minimum bid price
    /// @param startTime time in seconds to make listing available
    /// @param secondsUntilEndTime seconds for how long listing is available or zero to make indefinite
    /// @return listingId auction listed id
    function issue(address asset, bytes32 tokenId, uint256 startPrice, uint256 startTime, uint256 secondsUntilEndTime)
        external
        returns (uint256);

    /// cancels an auction
    /// @param listingId listing id
    function cancel(uint256 listingId) external;

    /// settles an auction by accepting a highest bid
    /// @param listingId listing id
    function settle(uint256 listingId) external;

    /// retrieves a bid for a listing id made by a buyer or reverts if not offered
    /// @param listingId listing id
    /// @param buyer buyer
    function getBid(uint256 listingId, address buyer) external view returns (LSP8Bid memory);

    /// confirms an auction has at least one bid offered
    /// @param listingId listing id
    function hasBids(uint256 listingId) external view returns (bool);

    /// retrieves the highest bid for a listing id made or reverts if non offered
    /// @param listingId listing id
    function getHighestBid(uint256 listingId) external view returns (LSP8Bid memory);

    /// offers a new bid or top offs existing if any
    /// @param listingId listing id
    function offer(uint256 listingId) external payable;

    /// retract a bid or revert if the bid is the current and auction is active
    /// @param listingId listing id
    function retract(uint256 listingId) external;
}
