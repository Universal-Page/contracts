// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Module} from "../common/Module.sol";
import {ILSP8Orders, LSP8Order} from "./ILSP8Orders.sol";

contract LSP8Orders is ILSP8Orders, Module {
    error NotPlacedOf(address asset, address buyer, bytes32[] tokenIds);
    error NotPlaced(uint256 id);
    error InvalidTokenCount(uint16 tokenCount);
    error AlreadyPlaced(address asset, address buyer, bytes32[] tokenIds);
    error InvalidAmount(uint256 expected, uint256 actual);
    error Unpaid(address buyer, uint256 amount);
    error InsufficientTokenCount(uint16 orderCount, uint16 offeredCount);
    error UnfulfilledToken(bytes32 tokenId);

    uint256 public totalOrders;
    mapping(address asset => mapping(address buyer => uint256[] ids)) private _orderIds;
    mapping(uint256 id => LSP8Order) private _orders;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_) external initializer {
        Module._initialize(newOwner_);
    }

    function _computeTokensKey(bytes32[] memory tokenIds) private pure returns (bytes32) {
        bytes32 key = 0;
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            key = keccak256(abi.encodePacked(key, tokenIds[i]));
        }
        return key;
    }

    function isPlacedOrderOf(address asset, address buyer, bytes32[] memory tokenIds)
        public
        view
        override
        returns (bool)
    {
        LSP8Order[] memory orders = ordersOf(asset, buyer);
        bytes32 tokensKey = _computeTokensKey(tokenIds);
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].tokenCount > 0 && _computeTokensKey(orders[i].tokenIds) == tokensKey) {
                return true;
            }
        }
        return false;
    }

    function orderOf(address asset, address buyer, bytes32[] memory tokenIds)
        external
        view
        override
        returns (LSP8Order memory)
    {
        LSP8Order[] memory orders = ordersOf(asset, buyer);
        bytes32 tokensKey = _computeTokensKey(tokenIds);
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].tokenCount > 0 && _computeTokensKey(orders[i].tokenIds) == tokensKey) {
                return orders[i];
            }
        }
        revert NotPlacedOf(asset, buyer, tokenIds);
    }

    function ordersOf(address asset, address buyer) public view returns (LSP8Order[] memory) {
        uint256[] memory orderIds = _orderIds[asset][buyer];
        LSP8Order[] memory orders = new LSP8Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            orders[i] = _orders[orderIds[i]];
        }
        return orders;
    }

    function isPlacedOrder(uint256 id) public view override returns (bool) {
        LSP8Order memory order = _orders[id];
        return order.tokenCount > 0;
    }

    function getOrder(uint256 id) public view override returns (LSP8Order memory) {
        if (!isPlacedOrder(id)) {
            revert NotPlaced(id);
        }
        return _orders[id];
    }

    function place(address asset, uint256 tokenPrice, bytes32[] memory tokenIds, uint16 tokenCount)
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (tokenCount == 0) {
            revert InvalidTokenCount(tokenCount);
        }

        if (tokenIds.length > 0 && tokenCount > tokenIds.length) {
            revert InvalidTokenCount(tokenCount);
        }

        address buyer = msg.sender;

        // verify buyer orders do not contain overlapping tokens
        {
            LSP8Order[] memory orders = ordersOf(asset, buyer);
            for (uint256 i = 0; i < orders.length; i++) {
                for (uint256 j = 0; j < orders[i].tokenIds.length; j++) {
                    for (uint256 k = 0; k < tokenIds.length; k++) {
                        if (orders[i].tokenIds[j] == tokenIds[k]) {
                            revert AlreadyPlaced(asset, buyer, tokenIds);
                        }
                    }
                }
            }
        }

        uint256 totalValue = tokenPrice * tokenCount;
        if (msg.value != totalValue) {
            revert InvalidAmount(totalValue, msg.value);
        }

        totalOrders += 1;
        uint256 orderId = totalOrders;

        _orderIds[asset][buyer].push(orderId);
        _orders[orderId] = LSP8Order({
            id: orderId,
            asset: asset,
            buyer: buyer,
            tokenPrice: tokenPrice,
            tokenIds: tokenIds,
            tokenCount: tokenCount
        });

        emit Placed(orderId, asset, buyer, tokenPrice, tokenIds, tokenCount);
        return orderId;
    }

    function cancel(uint256 id) external override whenNotPaused nonReentrant {
        address buyer = msg.sender;

        LSP8Order memory order = getOrder(id);
        if (order.buyer != buyer) {
            revert NotPlacedOf(order.asset, buyer, order.tokenIds);
        }

        delete _orders[id];

        // delete the order id from the buyer's orders
        {
            uint256[] storage orders = _orderIds[order.asset][order.buyer];
            uint256 index = orders.length;
            for (uint256 i = 0; i < orders.length; i++) {
                if (orders[i] == id) {
                    index = i;
                    break;
                }
            }
            if (index < orders.length) {
                orders[index] = orders[orders.length - 1];
                orders.pop();
            }
        }

        uint256 remainingValue = order.tokenPrice * order.tokenCount;
        (bool success,) = buyer.call{value: remainingValue}("");
        if (!success) {
            revert Unpaid(buyer, remainingValue);
        }

        emit Canceled(id, order.asset, buyer, order.tokenPrice, order.tokenIds, order.tokenCount);
    }

    function fill(uint256 id, address seller, bytes32[] memory tokenIds)
        external
        override
        whenNotPaused
        nonReentrant
        onlyMarketplace
    {
        uint256 tokenIdsCount = tokenIds.length;
        if (tokenIdsCount == 0) {
            revert InvalidTokenCount(0);
        }

        LSP8Order memory order = getOrder(id);

        // verify the order can be filled
        if (tokenIdsCount > order.tokenCount) {
            revert InsufficientTokenCount(order.tokenCount, uint16(tokenIdsCount));
        }

        // verify token ids are unique
        for (uint256 i = 0; i < tokenIdsCount; i++) {
            for (uint256 j = i + 1; j < tokenIdsCount; j++) {
                if (tokenIds[i] == tokenIds[j]) {
                    revert UnfulfilledToken(tokenIds[i]);
                }
            }
        }

        // verify requirements for the tokens
        if (order.tokenIds.length > 0) {
            // verify the tokens are in the order
            for (uint256 i = 0; i < tokenIdsCount; i++) {
                bytes32 tokenId = tokenIds[i];
                bool found = false;
                for (uint256 j = 0; j < order.tokenIds.length; j++) {
                    if (tokenId == order.tokenIds[j]) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    revert UnfulfilledToken(tokenIds[i]);
                }
            }

            // filter out the filled tokens
            bytes32[] memory remainingTokenIds = new bytes32[](order.tokenIds.length - tokenIdsCount);
            uint256 index = 0;

            for (uint256 i = 0; i < order.tokenIds.length; i++) {
                bytes32 tokenId = order.tokenIds[i];
                bool found = false;
                for (uint256 j = 0; j < tokenIdsCount; j++) {
                    if (tokenId == tokenIds[j]) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    remainingTokenIds[index] = tokenId;
                    index += 1;
                }
            }

            _orders[order.id].tokenIds = remainingTokenIds;
        }

        _orders[order.id].tokenCount = order.tokenCount - uint16(tokenIdsCount);

        uint256 filledValue = order.tokenPrice * tokenIdsCount;
        (bool success,) = msg.sender.call{value: filledValue}("");
        if (!success) {
            revert Unpaid(msg.sender, filledValue);
        }

        emit Filled(id, order.asset, seller, order.buyer, order.tokenPrice, tokenIds, order.tokenCount);
    }
}
