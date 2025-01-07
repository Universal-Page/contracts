// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

struct LSP8Order {
    uint256 id;
    address asset;
    address buyer;
    uint256 tokenPrice;
    bytes32[] tokenIds;
    uint16 tokenCount;
}

interface ILSP8Orders {
    /// an order was made for an asset
    event Placed(
        uint256 id,
        address indexed asset,
        address indexed buyer,
        uint256 tokenPrice,
        bytes32[] tokenIds,
        uint16 tokenCount
    );

    /// a buyer canceled an order
    event Canceled(
        uint256 id,
        address indexed asset,
        address indexed buyer,
        uint256 tokenPrice,
        bytes32[] tokenIds,
        uint16 tokenCount
    );

    /// an order was filled
    event Filled(
        uint256 id,
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        uint256 tokenPrice,
        bytes32[] tokenIds,
        uint16 tokenCount
    );

    /// confirms an order has been placed by a buyer
    /// @param asset asset address
    /// @param buyer buyer
    /// @return true if the order is placed
    function isPlacedOrderOf(address asset, address buyer) external view returns (bool);

    /// retrieves an order for an asset made by a buyer or reverts if not placed
    /// @param asset asset address
    /// @param buyer buyer
    /// @return order order
    function orderOf(address asset, address buyer) external view returns (LSP8Order memory);

    /// confirms an order has been placed by a buyer
    /// @param id order id
    /// @return true if the order is placed
    function isPlacedOrder(uint256 id) external view returns (bool);

    /// retrieves an order for an asset reverts if not placed
    /// @param id order id
    /// @return order order
    function getOrder(uint256 id) external view returns (LSP8Order memory);

    /// place an offer order with a fixed token price, token ids and number of tokens.
    /// @param asset asset address
    /// @param tokenPrice token price
    /// @param tokenIds token ids
    /// @param tokenCount number of tokens
    /// @return orderId order id
    function place(address asset, uint256 tokenPrice, bytes32[] calldata tokenIds, uint16 tokenCount)
        external
        payable
        returns (uint256);

    /// cancel an order by a buyer being a sender.
    /// @param id order id
    /// @dev reverts if the order is not placed
    function cancel(uint256 id) external;

    /// fill an order.
    /// @param id order id
    /// @param seller seller
    /// @param tokenIds token ids
    /// @dev reverts if the order is not placed
    function fill(uint256 id, address seller, bytes32[] calldata tokenIds) external;
}
