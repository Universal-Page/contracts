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
import {LSP8Listings, LSP8Listing} from "../../../src/marketplace/lsp8/LSP8Listings.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP8DigitalAssetMock} from "./LSP8DigitalAssetMock.sol";

contract LSP8ListingsTest is Test {
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
    event Updated(uint256 indexed id, address indexed asset, uint256 price, uint256 startTime, uint256 endTime);
    event Delisted(uint256 indexed id, address indexed asset);
    event Unlisted(uint256 indexed id, address indexed asset);

    LSP8Listings listings;
    address admin;
    address owner;
    LSP8DigitalAssetMock asset;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);

        asset = new LSP8DigitalAssetMock("Mock", "MCK", owner, 0, 0);

        listings = LSP8Listings(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP8Listings()), admin, abi.encodeWithSelector(LSP8Listings.initialize.selector, owner)
                )
            )
        );
    }

    function test_Initialized() public {
        assertTrue(!listings.paused());
        assertEq(owner, listings.owner());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        listings.pause();
        listings.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        listings.grantRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        listings.revokeRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        listings.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        listings.unpause();
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        listings.pause();
        vm.expectRevert("Pausable: paused");
        listings.list(address(asset), bytes32(uint256(1)), 1 ether, block.timestamp, 0);
        vm.expectRevert("Pausable: paused");
        listings.update(1, 1 ether, block.timestamp, 0);
        vm.expectRevert("Pausable: paused");
        listings.delist(1);
        vm.expectRevert("Pausable: paused");
        listings.unlist(1);
    }

    function testFuzz_NotListed(uint256 id) public {
        assertFalse(listings.isListed(id));
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.NotListed.selector, id));
        listings.getListing(id);
    }

    function testFuzz_NotActive(uint256 id) public {
        assertFalse(listings.isActiveListing(id));
    }

    function testFuzz_List(bytes32 tokenId, uint256 price, uint256 timestamp, uint256 secondsUntilEnd) public {
        vm.assume(timestamp >= 30 minutes);
        vm.assume(secondsUntilEnd > 0);
        vm.assume(secondsUntilEnd <= type(uint256).max - timestamp);

        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        vm.expectEmit(address(listings));
        emit Listed(
            1,
            address(asset),
            address(profile),
            address(profile),
            tokenId,
            price,
            timestamp,
            timestamp + secondsUntilEnd
        );
        uint256 id = listings.list(address(asset), tokenId, price, timestamp, secondsUntilEnd);
        assertEq(id, 1);

        assertEq(1, listings.totalListings());
        assertTrue(listings.isListed(1));
        assertEq(
            listings.isActiveListing(1), block.timestamp >= timestamp && block.timestamp < timestamp + secondsUntilEnd
        );

        LSP8Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(address(profile), listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(tokenId, listing.tokenId);
        assertEq(price, listing.price);
        assertEq(timestamp, listing.startTime);
        assertEq(timestamp + secondsUntilEnd, listing.endTime);
    }

    function testFuzz_ListIfOperator(bytes32 tokenId, uint256 price, uint256 timestamp, uint256 secondsUntilEnd)
        public
    {
        vm.assume(timestamp >= 30 minutes);
        vm.assume(secondsUntilEnd > 0);
        vm.assume(secondsUntilEnd <= type(uint256).max - timestamp);

        address operator = vm.addr(10);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");
        vm.prank(address(profile));
        asset.authorizeOperator(operator, tokenId, "");

        vm.prank(operator);
        vm.expectEmit(address(listings));
        emit Listed(
            1, address(asset), operator, address(profile), tokenId, price, timestamp, timestamp + secondsUntilEnd
        );
        listings.list(address(asset), tokenId, price, timestamp, secondsUntilEnd);

        assertEq(1, listings.totalListings());
        assertTrue(listings.isListed(1));
        assertEq(
            listings.isActiveListing(1), block.timestamp >= timestamp && block.timestamp < timestamp + secondsUntilEnd
        );

        LSP8Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(operator, listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(tokenId, listing.tokenId);
        assertEq(price, listing.price);
        assertEq(timestamp, listing.startTime);
        assertEq(timestamp + secondsUntilEnd, listing.endTime);
    }

    function test_Revert_ListIfNotOperator(bytes32 tokenId, address operator) public {
        (UniversalProfile profile,) = deployProfile();

        vm.assume(operator != address(profile));
        vm.assume(operator != admin);

        asset.mint(address(profile), tokenId, false, "");

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.InsufficientAuthorization.selector, operator, tokenId));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);
    }

    function testFuzz_Update(bytes32 tokenId, uint256 price, uint256 timestamp, uint256 secondsUntilEnd) public {
        vm.assume(timestamp >= 30 minutes);
        vm.assume(secondsUntilEnd > 0);
        vm.assume(secondsUntilEnd <= type(uint256).max - timestamp);

        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");
        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 0);

        vm.prank(address(profile));
        vm.expectEmit(address(listings));
        emit Updated(1, address(asset), price, timestamp, timestamp + secondsUntilEnd);
        listings.update(1, price, timestamp, secondsUntilEnd);

        assertTrue(listings.isListed(1));
        assertEq(
            listings.isActiveListing(1), block.timestamp >= timestamp && block.timestamp < timestamp + secondsUntilEnd
        );

        LSP8Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(address(profile), listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(tokenId, listing.tokenId);
        assertEq(price, listing.price);
        assertEq(timestamp, listing.startTime);
        assertEq(timestamp + secondsUntilEnd, listing.endTime);
    }

    function test_UpdateIfOperator() public {
        address operator = vm.addr(10);
        bytes32 tokenId = bytes32(0);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");
        vm.prank(address(profile));
        asset.authorizeOperator(operator, tokenId, "");

        vm.prank(operator);
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 3 days);

        vm.prank(operator);
        vm.expectEmit(address(listings));
        emit Updated(1, address(asset), 2 ether, block.timestamp + 3 hours, block.timestamp + 3 hours + 5 days);
        listings.update(1, 2 ether, block.timestamp + 3 hours, 5 days);

        assertTrue(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));

        LSP8Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(operator, listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(tokenId, listing.tokenId);
        assertEq(2 ether, listing.price);
        assertEq(block.timestamp + 3 hours, listing.startTime);
        assertEq(block.timestamp + 3 hours + 5 days, listing.endTime);
    }

    function testFuzz__Revert_UdateIfNotSeller(address seller) public {
        (UniversalProfile profile,) = deployProfile();

        vm.assume(seller != admin);
        vm.assume(seller != address(profile));

        bytes32 tokenId = bytes32(0);
        asset.mint(address(profile), tokenId, false, "");
        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 3 days);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.UnathorizedSeller.selector, seller));
        listings.update(1, 2 ether, block.timestamp + 3 hours, 5 days);
    }

    function testFuzz_Revert_UpdateIfInvalidListing(uint256 id) public {
        (UniversalProfile profile,) = deployProfile();
        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.NotListed.selector, id));
        listings.update(id, 1 ether, block.timestamp, 0);
    }

    function test_Delist() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 tokenId = bytes32(0);
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        assertTrue(listings.isListed(1));
        assertTrue(listings.isActiveListing(1));

        vm.prank(address(profile));
        vm.expectEmit(address(listings));
        emit Delisted(1, address(asset));
        listings.delist(1);

        assertFalse(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));
    }

    function testFuzz_Revert_DelistIfNotSeller(address seller) public {
        (UniversalProfile profile,) = deployProfile();

        vm.assume(seller != address(profile));
        vm.assume(seller != admin);

        bytes32 tokenId = bytes32(0);
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.UnathorizedSeller.selector, seller));
        listings.delist(1);
    }

    function test_Unlisted() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 tokenId = bytes32(0);
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        address marketplace = vm.addr(100);
        assertFalse(listings.hasRole(marketplace, MARKETPLACE_ROLE));

        vm.prank(owner);
        listings.grantRole(marketplace, MARKETPLACE_ROLE);
        assertTrue(listings.hasRole(marketplace, MARKETPLACE_ROLE));

        assertTrue(listings.isListed(1));
        assertTrue(listings.isActiveListing(1));

        vm.expectEmit(address(listings));
        emit Unlisted(1, address(asset));
        vm.prank(marketplace);
        listings.unlist(1);

        assertFalse(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));
    }

    function test_Revert_UnlistIfNotListed() public {
        address marketplace = vm.addr(100);
        vm.prank(owner);
        listings.grantRole(marketplace, MARKETPLACE_ROLE);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.NotListed.selector, 1));
        listings.unlist(1);
    }

    function testFuzz_Revert_UnlistIfNotActiveListing(bytes32 tokenId) public {
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        vm.warp(block.timestamp + 10 days);

        address marketplace = vm.addr(100);
        vm.prank(owner);
        listings.grantRole(marketplace, MARKETPLACE_ROLE);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.InactiveListing.selector, 1));
        listings.unlist(1);
    }

    function test_Revert_UnlistIfNotMarketplace() public {
        address marketplace = vm.addr(100);
        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(Module.IllegalAccess.selector, marketplace, MARKETPLACE_ROLE));
        listings.unlist(1);
    }

    function testFuzz_Revert_ListSameTokenForActiveListing(bytes32 tokenId) public {
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);
        assertTrue(listings.isListed(1));
        assertTrue(listings.isActiveListing(1));

        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.AlreadyListed.selector, 1));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);
    }

    function test_DelistIfListSameTokenForInactiveListing() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 tokenId = bytes32(0);
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);
        assertTrue(listings.isListed(1));
        assertTrue(listings.isActiveListing(1));

        vm.warp(block.timestamp + 10 days);
        assertTrue(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));

        vm.prank(address(profile));
        vm.expectEmit(address(listings));
        emit Delisted(1, address(asset));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        assertFalse(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));
        assertTrue(listings.isListed(2));
        assertTrue(listings.isActiveListing(2));
    }

    function test_DelistIfListSameTokenByDifferentSeller() public {
        (UniversalProfile alice,) = deployProfile();
        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);
        assertTrue(listings.isListed(1));
        assertTrue(listings.isActiveListing(1));
        assertEq(listings.getListing(1).seller, address(alice));

        (UniversalProfile bob,) = deployProfile();
        vm.prank(address(alice));
        asset.transfer(address(alice), address(bob), tokenId, false, "");

        vm.prank(address(bob));
        vm.expectEmit(address(listings));
        emit Delisted(1, address(asset));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);
        assertEq(listings.getListing(2).seller, address(bob));

        assertFalse(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));
        assertTrue(listings.isListed(2));
        assertTrue(listings.isActiveListing(2));
    }
}
