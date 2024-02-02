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
import {LSP7Offers, LSP7Offer} from "../../../src/marketplace/lsp7/LSP7Offers.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP7DigitalAssetMock} from "./LSP7DigitalAssetMock.sol";

contract LSP7OffersTest is Test {
    event Placed(
        uint256 indexed listingId, address indexed buyer, uint256 itemCount, uint256 totalPrice, uint256 expirationTime
    );
    event Canceled(uint256 indexed listingId, address indexed buyer, uint256 itemCount, uint256 totalPrice);
    event Accepted(uint256 indexed listingId, address indexed buyer, uint256 itemCount, uint256 totalPrice);

    LSP7Listings listings;
    LSP7Offers offers;
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
        offers = LSP7Offers(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP7Offers()),
                    admin,
                    abi.encodeWithSelector(LSP7Offers.initialize.selector, owner, listings)
                )
            )
        );
    }

    function test_Initialized() public {
        assertTrue(!offers.paused());
        assertEq(owner, offers.owner());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        offers.pause();
        offers.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        offers.grantRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        offers.revokeRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        offers.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        offers.unpause();
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        offers.pause();
        vm.expectRevert("Pausable: paused");
        offers.place(1, 1, 0 ether, 1 hours);
        vm.expectRevert("Pausable: paused");
        offers.cancel(1);
        vm.expectRevert("Pausable: paused");
        offers.accept(1, address(100));
    }

    function testFuzz_NotPlaced(uint256 listingId, address buyer) public {
        assertFalse(offers.isPlacedOffer(listingId, buyer));
        vm.expectRevert(abi.encodeWithSelector(LSP7Offers.NotPlaced.selector, listingId, buyer));
        offers.getOffer(listingId, buyer);
    }

    function testFuzz_NotActive(uint256 listingId, address buyer) public {
        assertFalse(offers.isActiveOffer(listingId, buyer));
    }

    function testFuzz_Place(
        uint256 listCount,
        uint256 listPrice,
        uint256 listDuration,
        uint256 offerCount,
        uint256 offerPrice,
        uint256 offerDuration
    ) public {
        vm.assume(listCount > 0 && listCount >= offerCount);
        vm.assume(listDuration <= type(uint256).max - block.timestamp);
        vm.assume(offerCount > 0);
        vm.assume(offerDuration >= 1 hours && offerDuration <= 28 days);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), listCount, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), listCount, listPrice, block.timestamp, listDuration);

        vm.deal(address(bob), offerPrice);
        vm.prank(address(bob));
        vm.expectEmit(address(offers));
        emit Placed(1, address(bob), offerCount, offerPrice, block.timestamp + offerDuration);
        offers.place{value: offerPrice}(1, offerCount, offerPrice, offerDuration);

        assertEq(address(bob).balance, 0);
        assertEq(address(offers).balance, offerPrice);
        assertTrue(offers.isPlacedOffer(1, address(bob)));
        assertTrue(offers.isActiveOffer(1, address(bob)));

        LSP7Offer memory offer = offers.getOffer(1, address(bob));
        assertEq(offer.itemCount, offerCount);
        assertEq(offer.totalPrice, offerPrice);
        assertEq(offer.expirationTime, block.timestamp + offerDuration);
    }

    function test_PlaceToTopOff() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 10 ether);
        {
            vm.prank(address(bob));
            vm.expectEmit(address(offers));
            emit Placed(1, address(bob), 5, 3 ether, block.timestamp + 1 hours);
            offers.place{value: 3 ether}(1, 5, 3 ether, 1 hours);

            assertEq(address(bob).balance, 7 ether);
            assertEq(address(offers).balance, 3 ether);
            assertTrue(offers.isPlacedOffer(1, address(bob)));
            assertTrue(offers.isActiveOffer(1, address(bob)));

            LSP7Offer memory offer = offers.getOffer(1, address(bob));
            assertEq(offer.itemCount, 5);
            assertEq(offer.totalPrice, 3 ether);
            assertEq(offer.expirationTime, block.timestamp + 1 hours);
        }
        {
            vm.prank(address(bob));
            vm.expectEmit(address(offers));
            emit Placed(1, address(bob), 10, 9 ether, block.timestamp + 3 hours);
            offers.place{value: 6 ether}(1, 10, 9 ether, 3 hours);

            assertEq(address(bob).balance, 1 ether);
            assertEq(address(offers).balance, 9 ether);
            assertTrue(offers.isPlacedOffer(1, address(bob)));
            assertTrue(offers.isActiveOffer(1, address(bob)));

            LSP7Offer memory offer = offers.getOffer(1, address(bob));
            assertEq(offer.itemCount, 10);
            assertEq(offer.totalPrice, 9 ether);
            assertEq(offer.expirationTime, block.timestamp + 3 hours);
        }
    }

    function test_Revert_PlaceInactiveListing() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp + 1 hours, 10 days);

        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LSP7Offers.InactiveListing.selector, 1));
        offers.place(1, 10, 0 ether, 1 hours);
    }

    function test_Cancel() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        offers.place{value: 1 ether}(1, 10, 1 ether, 1 hours);

        assertEq(address(bob).balance, 0 ether);
        assertEq(address(offers).balance, 1 ether);

        vm.prank(address(bob));
        vm.expectEmit(address(offers));
        emit Canceled(1, address(bob), 10, 1 ether);
        offers.cancel(1);

        assertEq(address(bob).balance, 1 ether);
        assertEq(address(offers).balance, 0 ether);
        assertFalse(offers.isPlacedOffer(1, address(bob)));
        assertFalse(offers.isActiveOffer(1, address(bob)));
    }

    function test_Revert_CancelIfNotBuyer() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        offers.place{value: 1 ether}(1, 10, 1 ether, 1 hours);

        vm.prank(address(100));
        vm.expectRevert(abi.encodeWithSelector(LSP7Offers.NotPlaced.selector, 1, address(100)));
        offers.cancel(1);
    }

    function test_Accept() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        address marketplace = vm.addr(100);
        assertFalse(offers.hasRole(marketplace, MARKETPLACE_ROLE));

        vm.prank(owner);
        offers.grantRole(marketplace, MARKETPLACE_ROLE);
        assertTrue(offers.hasRole(marketplace, MARKETPLACE_ROLE));

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        offers.place{value: 1 ether}(1, 10, 1 ether, 1 hours);

        assertEq(address(marketplace).balance, 0 ether);
        assertEq(address(bob).balance, 0 ether);
        assertEq(address(offers).balance, 1 ether);

        vm.prank(marketplace);
        vm.expectEmit(address(offers));
        emit Accepted(1, address(bob), 10, 1 ether);
        offers.accept(1, address(bob));

        assertEq(address(marketplace).balance, 1 ether);
        assertEq(address(bob).balance, 0 ether);
        assertEq(address(offers).balance, 0 ether);
    }

    function test_Revert_AcceptIfNotMarketplace() public {
        address marketplace = vm.addr(100);
        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(Module.IllegalAccess.selector, marketplace, MARKETPLACE_ROLE));
        offers.accept(1, address(101));
    }

    function test_Revert_AcceptIfInactiveListing() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        address marketplace = vm.addr(100);
        vm.prank(owner);
        offers.grantRole(marketplace, MARKETPLACE_ROLE);

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        offers.place{value: 1 ether}(1, 10, 1 ether, 1 hours);

        vm.warp(block.timestamp + 10 days);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP7Offers.InactiveListing.selector, 1));
        offers.accept(1, address(bob));
    }

    function test_Revert_AcceptIfInactiveOffer() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        address marketplace = vm.addr(100);
        vm.prank(owner);
        offers.grantRole(marketplace, MARKETPLACE_ROLE);

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        offers.place{value: 1 ether}(1, 10, 1 ether, 1 hours);

        assertTrue(offers.isPlacedOffer(1, address(bob)));
        assertTrue(offers.isActiveOffer(1, address(bob)));

        vm.warp(block.timestamp + 1 hours);

        assertTrue(offers.isPlacedOffer(1, address(bob)));
        assertFalse(offers.isActiveOffer(1, address(bob)));

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP7Offers.InactiveOffer.selector, 1, address(bob)));
        offers.accept(1, address(bob));
    }

    function test_Revert_AcceptIfListingCountInsufficient() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        address marketplace = vm.addr(100);
        vm.prank(owner);
        offers.grantRole(marketplace, MARKETPLACE_ROLE);

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        offers.place{value: 1 ether}(1, 10, 1 ether, 1 hours);

        vm.prank(address(alice));
        listings.update(1, 9, 1 ether, block.timestamp, 10 days);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP7Offers.InsufficientListingItemCount.selector, 1, 9, 10));
        offers.accept(1, address(bob));
    }
}
