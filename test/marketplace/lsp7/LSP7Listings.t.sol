// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {
    _LSP4_TOKEN_TYPE_TOKEN,
    _LSP4_TOKEN_TYPE_NFT,
    _LSP4_TOKEN_TYPE_COLLECTION
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {Module, MARKETPLACE_ROLE} from "../../../src/marketplace/common/Module.sol";
import {LSP7Listings, LSP7Listing} from "../../../src/marketplace/lsp7/LSP7Listings.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP7DigitalAssetMock} from "./LSP7DigitalAssetMock.sol";

contract LSP7ListingsTest is Test {
    event Listed(
        uint256 indexed id,
        address indexed asset,
        address seller,
        address indexed owner,
        uint256 itemCount,
        uint256 itemPrice,
        uint256 startTime,
        uint256 endTime
    );
    event Updated(
        uint256 indexed id,
        address indexed asset,
        uint256 itemCount,
        uint256 itemPrice,
        uint256 startTime,
        uint256 endTime
    );
    event Delisted(uint256 indexed id, address indexed asset);
    event Deducted(uint256 indexed id, address indexed asset, uint256 itemCount);
    event Unlisted(uint256 indexed id, address indexed asset);

    LSP7Listings listings;
    address admin;
    address owner;
    LSP7DigitalAssetMock asset;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);

        asset = new LSP7DigitalAssetMock("Mock", "MCK", owner, _LSP4_TOKEN_TYPE_NFT, true);

        listings = LSP7Listings(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP7Listings()), admin, abi.encodeWithSelector(LSP7Listings.initialize.selector, owner)
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
        listings.list(address(asset), address(100), 10, 1 ether, block.timestamp, 0);
        vm.expectRevert("Pausable: paused");
        listings.update(1, 10, 1 ether, block.timestamp, 0);
        vm.expectRevert("Pausable: paused");
        listings.delist(1);
        vm.expectRevert("Pausable: paused");
        listings.deduct(1, 2);
    }

    function testFuzz_NotListed(uint256 id) public {
        assertFalse(listings.isListed(id));
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.NotListed.selector, id));
        listings.getListing(id);
    }

    function testFuzz_NotActive(uint256 id) public {
        assertFalse(listings.isActiveListing(id));
    }

    function testFuzz_List(uint256 itemCount, uint256 itemPrice, uint256 timestamp, uint256 secondsUntilEnd) public {
        vm.assume(timestamp >= 30 minutes);
        vm.assume(itemCount > 0);
        vm.assume(secondsUntilEnd > 0);
        vm.assume(secondsUntilEnd <= type(uint256).max - timestamp);

        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), itemCount, false, "");

        vm.prank(address(profile));
        vm.expectEmit(address(listings));
        emit Listed(
            1,
            address(asset),
            address(profile),
            address(profile),
            itemCount,
            itemPrice,
            timestamp,
            timestamp + secondsUntilEnd
        );
        uint256 id = listings.list(address(asset), address(profile), itemCount, itemPrice, timestamp, secondsUntilEnd);
        assertEq(id, 1);

        assertEq(1, listings.totalListings());
        assertTrue(listings.isListed(1));
        assertEq(
            listings.isActiveListing(1), block.timestamp >= timestamp && block.timestamp < timestamp + secondsUntilEnd
        );

        LSP7Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(address(profile), listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(itemCount, listing.itemCount);
        assertEq(itemPrice, listing.itemPrice);
        assertEq(timestamp, listing.startTime);
        assertEq(timestamp + secondsUntilEnd, listing.endTime);
    }

    function testFuzz_ListIfOperator(uint256 itemCount, uint256 itemPrice, uint256 timestamp, uint256 secondsUntilEnd)
        public
    {
        vm.assume(timestamp >= 30 minutes);
        vm.assume(itemCount > 0);
        vm.assume(secondsUntilEnd > 0);
        vm.assume(secondsUntilEnd <= type(uint256).max - timestamp);

        address operator = vm.addr(10);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), itemCount, false, "");
        vm.prank(address(profile));
        asset.authorizeOperator(operator, itemCount, "");

        vm.prank(operator);
        vm.expectEmit(address(listings));
        emit Listed(
            1, address(asset), operator, address(profile), itemCount, itemPrice, timestamp, timestamp + secondsUntilEnd
        );
        listings.list(address(asset), address(profile), itemCount, itemPrice, timestamp, secondsUntilEnd);

        assertEq(1, listings.totalListings());
        assertTrue(listings.isListed(1));
        assertEq(
            listings.isActiveListing(1), block.timestamp >= timestamp && block.timestamp < timestamp + secondsUntilEnd
        );

        LSP7Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(operator, listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(itemCount, listing.itemCount);
        assertEq(itemPrice, listing.itemPrice);
        assertEq(timestamp, listing.startTime);
        assertEq(timestamp + secondsUntilEnd, listing.endTime);
    }

    function test_Revert_ListIfNotOperator(address operator) public {
        (UniversalProfile profile,) = deployProfile();

        vm.assume(operator != address(profile));
        vm.assume(operator != admin);

        asset.mint(address(profile), 100, false, "");

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.InsufficientAuthorization.selector, operator, 10, 0));
        listings.list(address(asset), address(profile), 10, 1 ether, block.timestamp, 10 days);
    }

    function testFuzz_Revert_ListIfOperatorExceedsAllowance(uint256 mintCount, uint256 allowance) public {
        vm.assume(mintCount > allowance);

        address operator = vm.addr(10);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), mintCount, false, "");
        vm.prank(address(profile));
        asset.authorizeOperator(operator, allowance, "");

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(LSP7Listings.InsufficientAuthorization.selector, operator, mintCount, allowance)
        );
        listings.list(address(asset), address(profile), mintCount, 1 ether, block.timestamp, 10 days);
    }

    function testFuzz_Update(uint256 itemCount, uint256 itemPrice, uint256 timestamp, uint256 secondsUntilEnd) public {
        vm.assume(timestamp >= 30 minutes);
        vm.assume(itemCount > 0);
        vm.assume(secondsUntilEnd > 0);
        vm.assume(secondsUntilEnd <= type(uint256).max - timestamp);

        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), itemCount, false, "");
        vm.prank(address(profile));
        listings.list(address(asset), address(profile), 1, 1 ether, block.timestamp, 0);

        vm.prank(address(profile));
        vm.expectEmit(address(listings));
        emit Updated(1, address(asset), itemCount, itemPrice, timestamp, timestamp + secondsUntilEnd);
        listings.update(1, itemCount, itemPrice, timestamp, secondsUntilEnd);

        assertTrue(listings.isListed(1));
        assertEq(
            listings.isActiveListing(1), block.timestamp >= timestamp && block.timestamp < timestamp + secondsUntilEnd
        );

        LSP7Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(address(profile), listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(itemCount, listing.itemCount);
        assertEq(itemPrice, listing.itemPrice);
        assertEq(timestamp, listing.startTime);
        assertEq(timestamp + secondsUntilEnd, listing.endTime);
    }

    function test_UpdateIfOperator() public {
        address operator = vm.addr(10);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), 10, false, "");
        vm.prank(address(profile));
        asset.authorizeOperator(operator, 10, "");

        vm.prank(operator);
        listings.list(address(asset), address(profile), 7, 1 ether, block.timestamp, 3 days);

        vm.prank(operator);
        vm.expectEmit(address(listings));
        emit Updated(1, address(asset), 10, 2 ether, block.timestamp + 3 hours, block.timestamp + 3 hours + 5 days);
        listings.update(1, 10, 2 ether, block.timestamp + 3 hours, 5 days);

        assertTrue(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));

        LSP7Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(operator, listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(10, listing.itemCount);
        assertEq(2 ether, listing.itemPrice);
        assertEq(block.timestamp + 3 hours, listing.startTime);
        assertEq(block.timestamp + 3 hours + 5 days, listing.endTime);
    }

    function testFuzz__Revert_UdateIfNotSeller(address seller) public {
        (UniversalProfile profile,) = deployProfile();

        vm.assume(seller != admin);
        vm.assume(seller != address(profile));

        asset.mint(address(profile), 10, false, "");
        vm.prank(address(profile));
        listings.list(address(asset), address(profile), 7, 1 ether, block.timestamp, 3 days);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.UnathorizedSeller.selector, seller));
        listings.update(1, 10, 2 ether, block.timestamp + 3 hours, 5 days);
    }

    function testFuzz_Revert_UpdateIfOperatorExceedsAllowance(uint256 mintCount, uint256 allowance) public {
        vm.assume(mintCount > allowance);

        address operator = vm.addr(10);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), mintCount, false, "");

        vm.prank(address(profile));
        asset.authorizeOperator(operator, mintCount, "");

        vm.prank(operator);
        listings.list(address(asset), address(profile), mintCount, 1 ether, block.timestamp, 10 days);

        vm.prank(address(profile));
        asset.authorizeOperator(operator, allowance, "");

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(LSP7Listings.InsufficientAuthorization.selector, operator, mintCount, allowance)
        );
        listings.update(1, mintCount, 1 ether, block.timestamp, 10 days);
    }

    function testFuzz_Revert_UpdateIfInvalidListing(uint256 id) public {
        (UniversalProfile profile,) = deployProfile();
        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.NotListed.selector, id));
        listings.update(id, 10, 1 ether, block.timestamp, 0);
    }

    function test_Delist() public {
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), 10, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), address(profile), 10, 1 ether, block.timestamp, 10 days);

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

        asset.mint(address(profile), 10, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), address(profile), 10, 1 ether, block.timestamp, 10 days);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.UnathorizedSeller.selector, seller));
        listings.delist(1);
    }

    function testFuzz_Deduct(uint256 listCount, uint256 deductCount) public {
        vm.assume(listCount > 0);
        vm.assume(deductCount > 0);
        vm.assume(listCount >= deductCount);

        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), listCount, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), address(profile), listCount, 1 ether, block.timestamp, 10 days);

        address marketplace = vm.addr(100);
        assertFalse(listings.hasRole(marketplace, MARKETPLACE_ROLE));

        vm.prank(owner);
        listings.grantRole(marketplace, MARKETPLACE_ROLE);
        assertTrue(listings.hasRole(marketplace, MARKETPLACE_ROLE));

        assertTrue(listings.isListed(1));
        assertTrue(listings.isActiveListing(1));

        vm.expectEmit(address(listings));
        emit Deducted(1, address(asset), deductCount);

        if (listCount == deductCount) {
            vm.expectEmit(address(listings));
            emit Unlisted(1, address(asset));
        }

        vm.prank(marketplace);
        listings.deduct(1, deductCount);

        assertEq(listings.isListed(1), listCount > deductCount);
        assertEq(listings.isActiveListing(1), listCount > deductCount);
    }

    function test_Revert_DeductIfNotListed() public {
        address marketplace = vm.addr(100);
        vm.prank(owner);
        listings.grantRole(marketplace, MARKETPLACE_ROLE);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.NotListed.selector, 1));
        listings.deduct(1, 10);
    }

    function test_Revert_DeductIfNotActiveListing() public {
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), 10, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), address(profile), 10, 1 ether, block.timestamp, 10 days);

        vm.warp(block.timestamp + 10 days);

        address marketplace = vm.addr(100);
        vm.prank(owner);
        listings.grantRole(marketplace, MARKETPLACE_ROLE);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.InactiveListing.selector, 1));
        listings.deduct(1, 10);
    }

    function test_Revert_DeductIfNotMarketplace() public {
        address marketplace = vm.addr(100);
        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(Module.IllegalAccess.selector, marketplace, MARKETPLACE_ROLE));
        listings.deduct(1, 10);
    }

    function test_Revert_DeductIfExceedItemCount() public {
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), 10, false, "");

        vm.prank(address(profile));
        listings.list(address(asset), address(profile), 10, 1 ether, block.timestamp, 10 days);

        address marketplace = vm.addr(100);
        vm.prank(owner);
        listings.grantRole(marketplace, MARKETPLACE_ROLE);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.InvalidDeduction.selector, 10, 11));
        listings.deduct(1, 11);
    }

    function test_Revert_ListMultipleTimes() public {
        address operator = vm.addr(10);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), 10, false, "");

        vm.prank(address(profile));
        asset.authorizeOperator(operator, 10, "");

        vm.prank(operator);
        listings.list(address(asset), address(profile), 7, 1 ether, block.timestamp, 10 days);

        assertEq(1, listings.totalListings());
        assertTrue(listings.isListed(1));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(LSP7Listings.InvalidListingAmount.selector, 11, 10));
        listings.list(address(asset), address(profile), 4, 1 ether, block.timestamp, 10 days);
    }

    function test_Revert_ListDivisibleNft() public {
        LSP7DigitalAssetMock invalidAsset = new LSP7DigitalAssetMock("Mock", "MCK", owner, _LSP4_TOKEN_TYPE_NFT, false);

        (UniversalProfile profile,) = deployProfile();
        invalidAsset.mint(address(profile), 10, false, "");

        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP7Listings.InvalidListingType.selector, address(invalidAsset), _LSP4_TOKEN_TYPE_NFT, false
            )
        );
        listings.list(address(invalidAsset), address(profile), 10, 1 ether, block.timestamp, 10 days);
    }

    function test_Revert_ListNonNft() public {
        LSP7DigitalAssetMock invalidAsset = new LSP7DigitalAssetMock("Mock", "MCK", owner, _LSP4_TOKEN_TYPE_TOKEN, true);

        (UniversalProfile profile,) = deployProfile();
        invalidAsset.mint(address(profile), 10, false, "");

        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP7Listings.InvalidListingType.selector, address(invalidAsset), _LSP4_TOKEN_TYPE_TOKEN, true
            )
        );
        listings.list(address(invalidAsset), address(profile), 10, 1 ether, block.timestamp, 10 days);
    }
}
