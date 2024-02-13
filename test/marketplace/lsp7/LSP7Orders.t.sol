// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {Module, MARKETPLACE_ROLE} from "../../../src/marketplace/common/Module.sol";
import {LSP7Listings, LSP7Listing} from "../../../src/marketplace/lsp7/LSP7Listings.sol";
import {LSP7Orders, LSP7Order} from "../../../src/marketplace/lsp7/LSP7Orders.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP7DigitalAssetMock} from "./LSP7DigitalAssetMock.sol";

contract LSP7OrdersTest is Test {
    event Placed(uint256 id, address indexed asset, address indexed buyer, uint256 itemPrice, uint256 itemCount);
    event Canceled(uint256 id, address indexed asset, address indexed buyer, uint256 itemPrice, uint256 itemCount);
    event Filled(
        uint256 id,
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        uint256 itemPrice,
        uint256 fillCount,
        uint256 totalCount
    );

    LSP7Orders orders;
    address admin;
    address owner;
    LSP7DigitalAssetMock asset;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);

        asset = new LSP7DigitalAssetMock("Mock", "MCK", owner, _LSP4_TOKEN_TYPE_NFT, true);

        orders = LSP7Orders(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP7Orders()),
                    admin,
                    abi.encodeWithSelector(LSP7Orders.initialize.selector, owner)
                )
            )
        );
    }

    function test_Initialized() public {
        assertTrue(!orders.paused());
        assertEq(owner, orders.owner());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        orders.pause();
        orders.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        orders.grantRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        orders.revokeRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        orders.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        orders.unpause();
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        orders.pause();
        vm.expectRevert("Pausable: paused");
        orders.place(address(asset), 1 ether, 1);
        vm.expectRevert("Pausable: paused");
        orders.cancel(1);
        vm.expectRevert("Pausable: paused");
        orders.fill(1, address(100), 100);
    }

    function testFuzz_NotPlacedOf(address someAsset, address buyer) public {
        assertFalse(orders.isPlacedOrderOf(someAsset, buyer));
        vm.expectRevert(abi.encodeWithSelector(LSP7Orders.NotPlacedOf.selector, someAsset, buyer));
        orders.orderOf(someAsset, buyer);
    }

    function testFuzz_NotPlaced(uint256 id) public {
        assertFalse(orders.isPlacedOrder(id));
        vm.expectRevert(abi.encodeWithSelector(LSP7Orders.NotPlaced.selector, id));
        orders.getOrder(id);
    }

    function testFuzz_Place(uint256 itemPrice, uint256 itemCount) public {
        vm.assume(itemPrice < 100_000_000 ether);
        vm.assume(itemCount > 0 && itemCount < 1_000_000);

        (UniversalProfile alice,) = deployProfile();

        vm.deal(address(alice), itemPrice * itemCount);
        vm.prank(address(alice));
        vm.expectEmit();
        emit Placed(1, address(asset), address(alice), itemPrice, itemCount);
        orders.place{value: itemPrice * itemCount}(address(asset), itemPrice, itemCount);

        assertTrue(orders.isPlacedOrder(1));
        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));

        LSP7Order memory order = orders.orderOf(address(asset), address(alice));
        assertEq(abi.encode(order), abi.encode(orders.getOrder(1)));
        assertEq(order.id, 1);
        assertEq(order.asset, address(asset));
        assertEq(order.buyer, address(alice));
        assertEq(order.itemPrice, itemPrice);
        assertEq(order.itemCount, itemCount);
    }

    function test_Revert_PlaceInvalidAmount() public {
        (UniversalProfile alice,) = deployProfile();

        vm.deal(address(alice), 1 ether);
        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(LSP7Orders.InvalidAmount.selector, 2 ether, 1 ether));
        orders.place{value: 1 ether}(address(asset), 1 ether, 2);
    }

    function test_Cancel() public {
        (UniversalProfile alice,) = deployProfile();

        vm.deal(address(alice), 1 ether);
        vm.prank(address(alice));
        orders.place{value: 1 ether}(address(asset), 0.5 ether, 2);

        assertTrue(orders.isPlacedOrder(1));
        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 0 ether);

        vm.prank(address(alice));
        vm.expectEmit();
        emit Canceled(1, address(asset), address(alice), 0.5 ether, 2);
        orders.cancel(1);

        assertFalse(orders.isPlacedOrder(1));
        assertFalse(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 1 ether);
    }

    function testFuzz_Revert_CancelIfNotBuyer(address buyer) public {
        (UniversalProfile alice,) = deployProfile();
        vm.assume(buyer != address(alice));

        vm.deal(address(alice), 1 ether);
        vm.prank(address(alice));
        orders.place{value: 1 ether}(address(asset), 0.5 ether, 2);

        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(LSP7Orders.NotPlacedOf.selector, address(asset), buyer));
        orders.cancel(1);

        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));
    }

    function testFuzz_Fill(uint256 itemPrice, uint256 itemCount, uint256 fillCount) public {
        vm.assume(itemPrice < 100_000_000 ether);
        vm.assume(itemCount > 0 && itemCount < 1_000_000);
        vm.assume(fillCount > 0 && fillCount < itemCount);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        vm.deal(address(alice), itemPrice * itemCount);
        vm.prank(address(alice));
        vm.expectEmit();
        emit Placed(1, address(asset), address(alice), itemPrice, itemCount);
        orders.place{value: itemPrice * itemCount}(address(asset), itemPrice, itemCount);

        LSP7Order memory order = orders.orderOf(address(asset), address(alice));
        assertEq(order.id, 1);
        assertEq(order.asset, address(asset));
        assertEq(order.buyer, address(alice));
        assertEq(order.itemPrice, itemPrice);
        assertEq(order.itemCount, itemCount);

        address marketplace = address(100);
        vm.prank(owner);
        orders.grantRole(marketplace, MARKETPLACE_ROLE);

        assertEq(marketplace.balance, 0 ether);

        vm.prank(marketplace);
        vm.expectEmit();
        emit Filled(1, address(asset), address(bob), address(alice), itemPrice, fillCount, itemCount);
        orders.fill(1, address(bob), fillCount);

        assertEq(marketplace.balance, fillCount * itemPrice);

        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));
        order = orders.orderOf(address(asset), address(alice));
        assertEq(order.id, 1);
        assertEq(order.asset, address(asset));
        assertEq(order.buyer, address(alice));
        assertEq(order.itemPrice, itemPrice);
        assertEq(order.itemCount, itemCount - fillCount);
    }

    function testFuzz_FillFully(uint256 itemPrice, uint256 itemCount) public {
        vm.assume(itemPrice < 100_000_000 ether);
        vm.assume(itemCount > 0 && itemCount < 1_000_000);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        vm.deal(address(alice), itemPrice * itemCount);
        vm.prank(address(alice));
        vm.expectEmit();
        emit Placed(1, address(asset), address(alice), itemPrice, itemCount);
        orders.place{value: itemPrice * itemCount}(address(asset), itemPrice, itemCount);

        LSP7Order memory order = orders.orderOf(address(asset), address(alice));
        assertEq(order.id, 1);
        assertEq(order.asset, address(asset));
        assertEq(order.buyer, address(alice));
        assertEq(order.itemPrice, itemPrice);
        assertEq(order.itemCount, itemCount);

        address marketplace = address(100);
        vm.prank(owner);
        orders.grantRole(marketplace, MARKETPLACE_ROLE);

        assertEq(marketplace.balance, 0 ether);

        vm.prank(marketplace);
        vm.expectEmit();
        emit Filled(1, address(asset), address(bob), address(alice), itemPrice, itemCount, itemCount);
        orders.fill(1, address(bob), itemCount);

        assertEq(marketplace.balance, itemCount * itemPrice);
        assertFalse(orders.isPlacedOrderOf(address(asset), address(alice)));
    }
}
