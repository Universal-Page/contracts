// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Module} from "../common/Module.sol";
import {ILSP7Orders, LSP7Order} from "./ILSP7Orders.sol";

contract LSP7Orders is ILSP7Orders, Module {
    error Unpaid(address buyer, uint256 amount);
    error NotPlacedOf(address asset, address buyer);
    error NotPlaced(uint256 id);
    error InvalidItemCount(uint256 itemCount);
    error AlreadyPlaced(address asset, address buyer);
    error InvalidAmount(uint256 expected, uint256 actual);
    error InsufficientItemCount(uint256 orderCount, uint256 offeredCount);

    uint256 public totalOrders;
    mapping(address asset => mapping(address buyer => uint256)) private _orderIds;
    mapping(uint256 id => LSP7Order) private _orders;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_) external initializer {
        Module._initialize(newOwner_);
    }

    function isPlacedOrderOf(address asset, address buyer) public view override returns (bool) {
        return isPlacedOrder(_orderIds[asset][buyer]);
    }

    function orderOf(address asset, address buyer) public view override returns (LSP7Order memory) {
        if (!isPlacedOrderOf(asset, buyer)) {
            revert NotPlacedOf(asset, buyer);
        }
        return _orders[_orderIds[asset][buyer]];
    }

    function isPlacedOrder(uint256 id) public view override returns (bool) {
        LSP7Order memory order = _orders[id];
        return order.itemCount > 0;
    }

    function getOrder(uint256 id) public view override returns (LSP7Order memory) {
        if (!isPlacedOrder(id)) {
            revert NotPlaced(id);
        }
        return _orders[id];
    }

    function place(address asset, uint256 itemPrice, uint256 itemCount)
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (itemCount == 0) {
            revert InvalidItemCount(itemCount);
        }
        address buyer = msg.sender;
        if (isPlacedOrderOf(asset, buyer)) {
            revert AlreadyPlaced(asset, buyer);
        }
        uint256 totalValue = itemPrice * itemCount;
        if (msg.value != totalValue) {
            revert InvalidAmount(totalValue, msg.value);
        }
        totalOrders += 1;
        uint256 orderId = totalOrders;
        _orderIds[asset][buyer] = orderId;
        _orders[orderId] =
            LSP7Order({id: orderId, asset: asset, buyer: buyer, itemPrice: itemPrice, itemCount: itemCount});
        emit Placed(orderId, asset, buyer, itemPrice, itemCount);
        return orderId;
    }

    function cancel(address asset) external override whenNotPaused nonReentrant {
        address buyer = msg.sender;
        LSP7Order memory order = orderOf(asset, buyer);
        delete _orders[order.id];
        delete _orderIds[asset][buyer];
        uint256 totalValue = order.itemPrice * order.itemCount;
        (bool success,) = buyer.call{value: totalValue}("");
        if (!success) {
            revert Unpaid(buyer, totalValue);
        }
        emit Canceled(order.id, asset, buyer, order.itemPrice, order.itemCount);
    }

    function fill(address asset, address seller, address buyer, uint256 itemCount)
        external
        override
        whenNotPaused
        nonReentrant
        onlyMarketplace
    {
        LSP7Order memory order = orderOf(asset, buyer);
        if (itemCount > order.itemCount) {
            revert InsufficientItemCount(order.itemCount, itemCount);
        }
        _orders[order.id].itemCount -= itemCount;
        uint256 totalValue = order.itemPrice * itemCount;
        (bool success,) = msg.sender.call{value: totalValue}("");
        if (!success) {
            revert Unpaid(msg.sender, totalValue);
        }
        emit Filled(order.id, asset, seller, buyer, order.itemPrice, itemCount);
    }
}
