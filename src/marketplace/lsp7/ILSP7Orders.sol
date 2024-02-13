// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

// Order for LSP7 asset
struct LSP7Order {
    uint256 id;
    address asset;
    address buyer;
    uint256 itemPrice;
    uint256 itemCount;
}

interface ILSP7Orders {
    /// an order was made for an asset
    event Placed(uint256 id, address indexed asset, address indexed buyer, uint256 itemPrice, uint256 itemCount);
    /// a buyer canceled an order
    event Canceled(uint256 id, address indexed asset, address indexed buyer, uint256 itemPrice, uint256 itemCount);
    /// an order was filled
    event Filled(
        uint256 id,
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        uint256 itemPrice,
        uint256 fillCount,
        uint256 totalCount
    );

    /// confirms an order has been placed by a buyer
    /// @param asset asset address
    /// @param buyer buyer
    function isPlacedOrderOf(address asset, address buyer) external view returns (bool);

    /// retrieves an order for an asset made by a buyer or reverts if not placed
    /// @param asset asset address
    /// @param buyer buyer
    function orderOf(address asset, address buyer) external view returns (LSP7Order memory);

    /// confirms an order has been placed by a buyer
    /// @param id order id
    function isPlacedOrder(uint256 id) external view returns (bool);

    /// retrieves an order for an asset reverts if not placed
    /// @param id order id
    function getOrder(uint256 id) external view returns (LSP7Order memory);

    /// place an offer order with a fixed item price, number of items and seconds until the offer is expired.
    /// @param asset asset address
    /// @param itemPrice item price
    /// @param itemCount number of items
    /// @return orderId order id
    function place(address asset, uint256 itemPrice, uint256 itemCount) external payable returns (uint256);

    /// cancel an order by a buyer being a sender.
    /// @param id order id
    function cancel(uint256 id) external;

    /// fill an order.
    /// @param id order id
    /// @param seller seller
    /// @param itemCount number of items
    function fill(uint256 id, address seller, uint256 itemCount) external;
}
