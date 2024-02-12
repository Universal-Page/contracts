// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {Module} from "../common/Module.sol";
import {ILSP7Orders, LSP7Order} from "./ILSP7Orders.sol";

contract LSP7Orders is ILSP7Orders, Module {
    error Unpaid(address buyer, uint256 amount);
    error NotPlaced(address asset, address buyer);
    error Inactive(address asset, address buyer);
    error InvalidItemCount(uint256 itemCount);
    error InvalidDuration(uint256 secondsUntilExpiration);
    error AlreadyPlaced(address asset, address buyer);
    error InvalidAmount(uint256 expected, uint256 actual);
    error InsufficientItemCount(uint256 orderCount, uint256 offeredCount);

    uint256 public totalOrders;
    mapping(address asset => mapping(address buyer => LSP7Order order)) private _orders;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_) external initializer {
        Module._initialize(newOwner_);
    }

    function isPlacedOrder(address asset, address buyer) public view override returns (bool) {
        LSP7Order memory order = _orders[asset][buyer];
        return order.itemCount > 0;
    }

    function isActiveOrder(address asset, address buyer) public view override returns (bool) {
        LSP7Order memory order = _orders[asset][buyer];
        return (order.itemCount > 0) && (order.expirationTime > block.timestamp);
    }

    function getOrder(address asset, address buyer) public view override returns (LSP7Order memory) {
        if (!isPlacedOrder(asset, buyer)) {
            revert NotPlaced(asset, buyer);
        }
        return _orders[asset][buyer];
    }

    function place(address asset, uint256 itemPrice, uint256 itemCount, uint256 secondsUntilExpiration)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        if (itemCount == 0) {
            revert InvalidItemCount(itemCount);
        }
        if ((secondsUntilExpiration < 1 hours) || (secondsUntilExpiration > 28 days)) {
            revert InvalidDuration(secondsUntilExpiration);
        }
        address buyer = msg.sender;
        if (isPlacedOrder(asset, buyer)) {
            revert AlreadyPlaced(asset, buyer);
        }
        uint256 totalValue = itemPrice * itemCount;
        if (msg.value != totalValue) {
            revert InvalidAmount(totalValue, msg.value);
        }
        uint256 expirationTime = block.timestamp + secondsUntilExpiration;
        totalOrders += 1;
        _orders[asset][buyer] =
            LSP7Order({id: totalOrders, itemPrice: itemPrice, itemCount: itemCount, expirationTime: expirationTime});
        emit Placed(asset, buyer, itemPrice, itemCount, expirationTime);
    }

    function cancel(address asset) external override whenNotPaused nonReentrant {
        LSP7Order memory order = getOrder(asset, msg.sender);
        uint256 totalValue = order.itemPrice * order.itemCount;
        delete _orders[asset][msg.sender];
        (bool success,) = msg.sender.call{value: totalValue}("");
        if (!success) {
            revert Unpaid(msg.sender, totalValue);
        }
        emit Canceled(asset, msg.sender, order.itemCount, order.itemPrice);
    }

    function fill(address asset, address seller, address buyer, uint256 itemCount)
        external
        override
        whenNotPaused
        nonReentrant
        onlyMarketplace
    {
        LSP7Order memory order = getOrder(asset, buyer);
        if (!isActiveOrder(asset, buyer)) {
            revert Inactive(asset, buyer);
        }
        if (itemCount > order.itemCount) {
            revert InsufficientItemCount(order.itemCount, itemCount);
        }
        _orders[asset][buyer].itemCount -= itemCount;
        uint256 totalValue = order.itemPrice * itemCount;
        (bool success,) = msg.sender.call{value: totalValue}("");
        if (!success) {
            revert Unpaid(msg.sender, totalValue);
        }
        emit Filled(asset, seller, buyer, order.itemPrice, itemCount);
    }
}
