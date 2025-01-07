// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {Module, MARKETPLACE_ROLE} from "../../../src/marketplace/common/Module.sol";
import {LSP8Order, LSP8Orders} from "../../../src/marketplace/lsp8/LSP8Orders.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP8DigitalAssetMock} from "./LSP8DigitalAssetMock.sol";

contract LSP8OrdersTest is Test {
    event Placed(
        uint256 id,
        address indexed asset,
        address indexed buyer,
        uint256 tokenPrice,
        bytes32[] tokenIds,
        uint16 tokenCount
    );
    event Canceled(
        uint256 id,
        address indexed asset,
        address indexed buyer,
        uint256 tokenPrice,
        bytes32[] tokenIds,
        uint16 tokenCount
    );
    event Filled(
        uint256 id,
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        uint256 tokenPrice,
        bytes32[] tokenIds,
        uint16 tokenCount
    );

    LSP8Orders orders;
    address admin;
    address owner;
    LSP8DigitalAssetMock asset;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);

        asset = new LSP8DigitalAssetMock("Mock", "MCK", owner, 0, 0);

        orders = LSP8Orders(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP8Orders()), admin, abi.encodeWithSelector(LSP8Orders.initialize.selector, owner)
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

    function testFuzz_Revert_WhenPaused(bytes32[] memory tokenIds) public {
        vm.prank(owner);
        orders.pause();

        vm.expectRevert("Pausable: paused");
        orders.place(address(asset), 1 ether, tokenIds, 1);

        vm.expectRevert("Pausable: paused");
        orders.cancel(1);

        vm.expectRevert("Pausable: paused");
        orders.fill(1, address(100), tokenIds);
    }

    function testFuzz_NotPlacedOf(address someAsset, address buyer) public {
        assertFalse(orders.isPlacedOrderOf(someAsset, buyer));
        vm.expectRevert(abi.encodeWithSelector(LSP8Orders.NotPlacedOf.selector, someAsset, buyer));
        orders.orderOf(someAsset, buyer);
    }

    function testFuzz_NotPlaced(uint256 id) public {
        assertFalse(orders.isPlacedOrder(id));
        vm.expectRevert(abi.encodeWithSelector(LSP8Orders.NotPlaced.selector, id));
        orders.getOrder(id);
    }

    function testFuzz_Place(uint256 tokenPrice, bytes32[] memory tokenIds, uint16 tokenCount) public {
        vm.assume(tokenPrice < 1_000 ether);
        vm.assume(tokenIds.length <= 100);
        vm.assume(tokenCount > 0);
        vm.assume(tokenCount <= tokenIds.length);

        (UniversalProfile alice,) = deployProfile();

        vm.deal(address(alice), tokenPrice * tokenCount);
        vm.prank(address(alice));
        vm.expectEmit();
        emit Placed(1, address(asset), address(alice), tokenPrice, tokenIds, tokenCount);
        orders.place{value: tokenPrice * tokenCount}(address(asset), tokenPrice, tokenIds, tokenCount);

        assertTrue(orders.isPlacedOrder(1));
        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));

        LSP8Order memory order = orders.orderOf(address(asset), address(alice));
        assertEq(abi.encode(order), abi.encode(orders.getOrder(1)));
        assertEq(order.id, 1);
        assertEq(order.asset, address(asset));
        assertEq(order.buyer, address(alice));
        assertEq(order.tokenPrice, tokenPrice);
        assertEq(abi.encode(order.tokenIds), abi.encode(tokenIds));
        assertEq(order.tokenCount, tokenCount);
    }

    function test_Revert_InvalidTokenCount() public {
        (UniversalProfile alice,) = deployProfile();
        vm.deal(address(alice), 100 ether);

        {
            bytes32[] memory tokenIds = new bytes32[](0);

            vm.prank(address(alice));
            vm.expectRevert(abi.encodeWithSelector(LSP8Orders.InvalidTokenCount.selector, 0));
            orders.place{value: 1 ether}(address(asset), 1 ether, tokenIds, 0);
        }

        {
            bytes32[] memory tokenIds = new bytes32[](1);
            tokenIds[0] = keccak256("token1");

            vm.prank(address(alice));
            vm.expectRevert(abi.encodeWithSelector(LSP8Orders.InvalidTokenCount.selector, 0));
            orders.place{value: 1 ether}(address(asset), 1 ether, tokenIds, 0);
        }

        {
            bytes32[] memory tokenIds = new bytes32[](2);
            tokenIds[0] = keccak256("token1");
            tokenIds[1] = keccak256("token2");

            vm.prank(address(alice));
            vm.expectRevert(abi.encodeWithSelector(LSP8Orders.InvalidTokenCount.selector, 3));
            orders.place{value: 2 ether}(address(asset), 1 ether, tokenIds, 3);
        }
    }

    function test_Revert_AlreadyPlaced() public {
        bytes32[] memory tokenIds = new bytes32[](1);
        tokenIds[0] = keccak256("token1");

        (UniversalProfile alice,) = deployProfile();
        vm.deal(address(alice), 2 ether);

        vm.prank(address(alice));
        orders.place{value: 1 ether}(address(asset), 1 ether, tokenIds, 1);

        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(LSP8Orders.AlreadyPlaced.selector, address(asset), address(alice)));
        orders.place{value: 1 ether}(address(asset), 1 ether, tokenIds, 1);
    }

    function test_Revert_InvalidAmount() public {
        bytes32[] memory tokenIds = new bytes32[](1);
        tokenIds[0] = keccak256("token1");

        (UniversalProfile alice,) = deployProfile();
        vm.deal(address(alice), 1 ether);

        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(LSP8Orders.InvalidAmount.selector, 1 ether, 0.5 ether));
        orders.place{value: 0.5 ether}(address(asset), 1 ether, tokenIds, 1);
    }

    function test_Cancel() public {
        bytes32[] memory tokenIds = new bytes32[](1);
        tokenIds[0] = keccak256("token1");

        (UniversalProfile alice,) = deployProfile();
        vm.deal(address(alice), 1 ether);

        vm.prank(address(alice));
        orders.place{value: 1 ether}(address(asset), 1 ether, tokenIds, 1);

        vm.prank(address(alice));
        vm.expectEmit();
        emit Canceled(1, address(asset), address(alice), 1 ether, tokenIds, 1);
        orders.cancel(1);

        assertFalse(orders.isPlacedOrder(1));
        assertFalse(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 1 ether);
    }

    function test_Revert_CancelIfNotBuyer() public {
        bytes32[] memory tokenIds = new bytes32[](1);
        tokenIds[0] = keccak256("token1");

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        vm.deal(address(alice), 1 ether);
        vm.prank(address(alice));
        orders.place{value: 1 ether}(address(asset), 1 ether, tokenIds, 1);

        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 0 ether);

        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LSP8Orders.NotPlacedOf.selector, address(asset), address(bob)));
        orders.cancel(1);

        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 0 ether);
    }

    function testFuzz_Fill(uint16 tokenCount, uint16 fillCount) public {
        vm.assume(tokenCount > 0 && tokenCount < 100);
        vm.assume(fillCount > 0 && fillCount <= tokenCount);

        uint256 tokenPrice = 1 ether;

        bytes32[] memory tokenIds = new bytes32[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = keccak256(abi.encodePacked(i));
        }

        bytes32[] memory fillTokenIds = new bytes32[](fillCount);
        for (uint256 i = 0; i < fillCount; i++) {
            fillTokenIds[i] = tokenIds[i];
        }

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        vm.deal(address(alice), tokenPrice * tokenCount);

        vm.prank(address(alice));
        orders.place{value: tokenPrice * tokenCount}(address(asset), tokenPrice, tokenIds, tokenCount);

        address marketplace = address(100);
        vm.prank(owner);
        orders.grantRole(marketplace, MARKETPLACE_ROLE);

        vm.prank(marketplace);
        vm.expectEmit();
        emit Filled(1, address(asset), address(bob), address(alice), tokenPrice, fillTokenIds, fillCount);
        orders.fill(1, address(bob), fillTokenIds);
    }

    function test_CancelAfterPartialFill() public {
        uint256 tokenPrice = 1 ether;

        bytes32[] memory tokenIds = new bytes32[](2);
        tokenIds[0] = keccak256("token1");
        tokenIds[1] = keccak256("token2");

        bytes32[] memory fillTokenIds = new bytes32[](1);
        fillTokenIds[0] = tokenIds[0];

        bytes32[] memory cancelTokenIds = new bytes32[](1);
        cancelTokenIds[0] = tokenIds[1];

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        vm.deal(address(alice), tokenPrice * 2);

        vm.prank(address(alice));
        vm.expectEmit();
        emit Placed(1, address(asset), address(alice), tokenPrice, tokenIds, 2);
        orders.place{value: tokenPrice * 2}(address(asset), tokenPrice, tokenIds, 2);

        address marketplace = address(100);
        vm.prank(owner);
        orders.grantRole(marketplace, MARKETPLACE_ROLE);

        assertTrue(orders.isPlacedOrder(1));
        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 0 ether);
        assertEq(address(bob).balance, 0 ether);
        assertEq(marketplace.balance, 0 ether);
        assertEq(address(orders).balance, 2 ether);

        vm.prank(marketplace);
        vm.expectEmit();
        emit Filled(1, address(asset), address(bob), address(alice), tokenPrice, fillTokenIds, 1);
        orders.fill(1, address(bob), fillTokenIds);

        assertTrue(orders.isPlacedOrder(1));
        assertTrue(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 0 ether);
        assertEq(address(bob).balance, 0 ether);
        assertEq(marketplace.balance, 1 ether);
        assertEq(address(orders).balance, 1 ether);

        vm.prank(address(alice));
        vm.expectEmit();
        emit Canceled(1, address(asset), address(alice), tokenPrice, cancelTokenIds, 1);
        orders.cancel(1);

        assertFalse(orders.isPlacedOrder(1));
        assertFalse(orders.isPlacedOrderOf(address(asset), address(alice)));
        assertEq(address(alice).balance, 1 ether);
        assertEq(address(bob).balance, 0 ether);
        assertEq(marketplace.balance, 1 ether);
        assertEq(address(orders).balance, 0 ether);
    }
}
