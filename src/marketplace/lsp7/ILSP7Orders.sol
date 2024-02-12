// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

// Order for LSP7 asset
struct LSP7Order {
    uint256 id;
    uint256 itemPrice;
    uint256 itemCount;
    uint256 expirationTime;
}

interface ILSP7Orders {
    /// an order was made for an asset
    event Placed(
        address indexed asset, address indexed buyer, uint256 itemPrice, uint256 itemCount, uint256 expirationTime
    );
    /// a buyer canceled an order
    event Canceled(address indexed asset, address indexed buyer, uint256 itemPrice, uint256 itemCount);
    /// an order was filled
    event Filled(
        address indexed asset, address indexed seller, address indexed buyer, uint256 itemPrice, uint256 itemCount
    );

    /// confirms an order has been placed by a buyer
    /// @param asset asset address
    /// @param buyer buyer
    function isPlacedOrder(address asset, address buyer) external view returns (bool);

    /// confirms an order with asset address and buyer is active
    /// @param asset asset address
    /// @param buyer buyer
    function isActiveOrder(address asset, address buyer) external view returns (bool);

    /// retrieves an order for an asset made by a buyer or reverts if not placed
    /// @param asset asset address
    /// @param buyer buyer
    function getOrder(address asset, address buyer) external view returns (LSP7Order memory);

    /// place an offer order with a fixed item price, number of items and seconds until the offer is expired.
    /// @param asset asset address
    /// @param itemPrice item price
    /// @param itemCount number of items
    /// @param secondsUntilExpiration time in seconds until offer is expired
    function place(address asset, uint256 itemPrice, uint256 itemCount, uint256 secondsUntilExpiration)
        external
        payable;

    /// cancel an order by a buyer being a sender.
    /// @param asset asset address
    function cancel(address asset) external;

    /// fill an order.
    /// @param asset asset address
    /// @param seller seller
    /// @param buyer buyer
    /// @param itemCount number of items
    function fill(address asset, address seller, address buyer, uint256 itemCount) external;
}
