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
import {LSP8Auctions, LSP8Auction, LSP8Bid} from "../../../src/marketplace/lsp8/LSP8Auctions.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP8DigitalAssetMock} from "./LSP8DigitalAssetMock.sol";

contract LSP8AuctionsTest is Test {
    event Issued(
        uint256 indexed listingId,
        address indexed seller,
        address indexed owner,
        bytes32 tokenId,
        uint256 startPrice,
        uint256 startTime,
        uint256 endTime
    );
    event Canceled(uint256 indexed listingId, address indexed seller, address indexed owner, bytes32 tokenId);
    event Settled(
        uint256 indexed listingId,
        address seller,
        address indexed owner,
        bytes32 tokenId,
        address indexed buyer,
        uint256 totalPaid
    );
    event Offered(
        uint256 indexed listingId,
        address seller,
        address indexed owner,
        bytes32 tokenId,
        address indexed buyer,
        uint256 totalPaid
    );
    event Retracted(uint256 indexed listingId, address indexed buyer, uint256 totalPaid);

    LSP8Listings listings;
    LSP8Auctions auctions;
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
        auctions = LSP8Auctions(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP8Auctions()),
                    admin,
                    abi.encodeWithSelector(LSP8Auctions.initialize.selector, owner, listings)
                )
            )
        );

        vm.prank(owner);
        listings.grantRole(address(auctions), MARKETPLACE_ROLE);
    }

    function test_Initialized() public {
        assertTrue(!auctions.paused());
        assertEq(owner, auctions.owner());
        assertEq(address(listings), address(auctions.listings()));
        assertEq(0, auctions.minBidDetlaPoints());
        assertEq(5 minutes, auctions.bidTimeExtension());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        auctions.pause();
        auctions.unpause();
        auctions.setMinBidDetlaPoints(5_000);
        auctions.setBidTimeExtension(5 minutes);
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        auctions.grantRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        auctions.revokeRole(address(100), MARKETPLACE_ROLE);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        auctions.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        auctions.unpause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        auctions.setMinBidDetlaPoints(5_000);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        auctions.setBidTimeExtension(5 minutes);
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        auctions.pause();
        vm.expectRevert("Pausable: paused");
        auctions.issue(address(100), bytes32(0), 1 ether, block.timestamp, 1 hours);
        vm.expectRevert("Pausable: paused");
        auctions.cancel(1);
        vm.expectRevert("Pausable: paused");
        auctions.settle(1);
        vm.expectRevert("Pausable: paused");
        auctions.offer(1);
        vm.expectRevert("Pausable: paused");
        auctions.retract(1);
    }

    function testFuzz_NotIssues(uint256 listingId) public {
        assertFalse(auctions.isIssued(listingId));
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.NotIssued.selector, listingId));
        auctions.getAuction(listingId);
    }

    function testFuzz_NotActive(uint256 listingId) public {
        assertFalse(auctions.isActiveAuction(listingId));
    }

    function testFuzz_NotOffered(uint256 listingId, address buyer) public {
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.NotOffered.selector, listingId, buyer));
        auctions.getBid(listingId, buyer);
    }

    function testFuzz_NoBids(uint256 listingId) public {
        assertFalse(auctions.hasBids(listingId));
    }

    function testFuzz_NoHighestBid(uint256 listingId) public {
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.NotOffered.selector, listingId, address(0)));
        auctions.getHighestBid(listingId);
    }

    function testFuzz_Issue(bytes32 tokenId, uint256 startPrice) public {
        (UniversalProfile profile,) = deployProfile();

        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        vm.expectEmit(address(auctions));
        emit Issued(
            1, address(profile), address(profile), tokenId, startPrice, block.timestamp, block.timestamp + 7 days
        );
        auctions.issue(address(asset), tokenId, startPrice, block.timestamp, 7 days);

        assertTrue(listings.isActiveListing(1));
        LSP8Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(tokenId, listing.tokenId);
        assertEq(address(auctions), listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(startPrice, listing.price);
        assertEq(block.timestamp, listing.startTime);
        assertEq(0, listing.endTime);

        assertTrue(auctions.isActiveAuction(1));
        LSP8Auction memory auction = auctions.getAuction(1);
        assertEq(address(profile), auction.seller);
        assertEq(startPrice, auction.startPrice);
        assertEq(block.timestamp, auction.startTime);
        assertEq(block.timestamp + 7 days, auction.endTime);
    }

    function test_IssueAsOperator() public {
        address operator = vm.addr(10);
        bytes32 tokenId = bytes32(0);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");
        vm.prank(address(profile));
        asset.authorizeOperator(operator, tokenId, "");

        vm.prank(operator);
        vm.expectEmit(address(auctions));
        emit Issued(1, operator, address(profile), tokenId, 1 ether, block.timestamp, block.timestamp + 7 days);
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        assertTrue(listings.isActiveListing(1));
        LSP8Listing memory listing = listings.getListing(1);
        assertEq(address(asset), listing.asset);
        assertEq(tokenId, listing.tokenId);
        assertEq(address(auctions), listing.seller);
        assertEq(address(profile), listing.owner);
        assertEq(1 ether, listing.price);
        assertEq(block.timestamp, listing.startTime);
        assertEq(0, listing.endTime);

        assertTrue(auctions.isActiveAuction(1));
        LSP8Auction memory auction = auctions.getAuction(1);
        assertEq(operator, auction.seller);
        assertEq(1 ether, auction.startPrice);
        assertEq(block.timestamp, auction.startTime);
        assertEq(block.timestamp + 7 days, auction.endTime);
    }

    function test_Cancel() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.prank(address(profile));
        vm.expectEmit(address(auctions));
        emit Canceled(1, address(profile), address(profile), tokenId);
        auctions.cancel(1);

        assertFalse(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));
        assertFalse(auctions.isIssued(1));
        assertFalse(auctions.isActiveAuction(1));
    }

    function test_Revert_CancelIfNotSeller() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.prank(address(100));
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.UnathorizedSeller.selector, address(100)));
        auctions.cancel(1);
    }

    function test_Revert_DelistIfNotAuctions() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(LSP8Listings.UnathorizedSeller.selector, address(profile)));
        listings.delist(1);
    }

    function test_Offer() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        (UniversalProfile carol,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);
        assertFalse(auctions.hasBids(1));

        {
            vm.deal(address(bob), 1 ether);
            vm.prank(address(bob));
            vm.expectEmit(address(auctions));
            emit Offered(1, address(alice), address(alice), tokenId, address(bob), 1 ether);
            auctions.offer{value: 1 ether}(1);

            assertTrue(auctions.hasBids(1));
            LSP8Bid memory highestBid = auctions.getHighestBid(1);
            assertEq(address(bob), highestBid.buyer);
            assertEq(1 ether, highestBid.totalPaid);
            LSP8Bid memory bid = auctions.getBid(1, address(bob));
            assertEq(address(bob), bid.buyer);
            assertEq(1 ether, bid.totalPaid);
        }
        {
            vm.deal(address(carol), 1.5 ether);
            vm.prank(address(carol));
            vm.expectEmit(address(auctions));
            emit Offered(1, address(alice), address(alice), tokenId, address(carol), 1.5 ether);
            auctions.offer{value: 1.5 ether}(1);

            assertTrue(auctions.hasBids(1));
            LSP8Bid memory highestBid = auctions.getHighestBid(1);
            assertEq(address(carol), highestBid.buyer);
            assertEq(1.5 ether, highestBid.totalPaid);
            LSP8Bid memory bid = auctions.getBid(1, address(carol));
            assertEq(address(carol), bid.buyer);
            assertEq(1.5 ether, bid.totalPaid);
        }
    }

    function test_Retract() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        (UniversalProfile carol,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);
        assertFalse(auctions.hasBids(1));

        {
            vm.deal(address(bob), 1 ether);
            vm.prank(address(bob));
            vm.expectEmit(address(auctions));
            emit Offered(1, address(alice), address(alice), tokenId, address(bob), 1 ether);
            auctions.offer{value: 1 ether}(1);
        }
        {
            vm.deal(address(carol), 1.5 ether);
            vm.prank(address(carol));
            vm.expectEmit(address(auctions));
            emit Offered(1, address(alice), address(alice), tokenId, address(carol), 1.5 ether);
            auctions.offer{value: 1.5 ether}(1);
        }

        assertEq(0 ether, address(bob).balance);
        vm.prank(address(bob));
        vm.expectEmit(address(auctions));
        emit Retracted(1, address(bob), 1 ether);
        auctions.retract(1);
        assertEq(1 ether, address(bob).balance);
    }

    function test_Revert_RetractIfHighestBid() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        auctions.offer{value: 1 ether}(1);

        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.HighestOfferPending.selector, 1, address(bob)));
        auctions.retract(1);
    }

    function test_RetractHighestBid() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        auctions.offer{value: 1 ether}(1);

        vm.warp(block.timestamp + 7 days + 24 hours);

        vm.prank(address(bob));
        vm.expectEmit(address(auctions));
        emit Retracted(1, address(bob), 1 ether);
        auctions.retract(1);
        assertEq(1 ether, address(bob).balance);
    }

    function test_Revert_OfferIfNotStarted() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp + 1 minutes, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.InactiveAuction.selector, 1));
        auctions.offer{value: 1 ether}(1);
    }

    function test_Revert_OfferIfEnded() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);
        vm.warp(block.timestamp + 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.InactiveAuction.selector, 1));
        auctions.offer{value: 1 ether}(1);
    }

    function test_Revert_OfferIfTooLow() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 0.9 ether);
        vm.prank(address(bob));
        vm.expectRevert(
            abi.encodeWithSelector(LSP8Auctions.InsufficientOfferAmount.selector, 1, address(bob), 1 ether, 0.9 ether)
        );
        auctions.offer{value: 0.9 ether}(1);
    }

    function test_Revert_OfferIfBelowPriceDelta() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.prank(owner);
        auctions.setMinBidDetlaPoints(10_000);

        // initial offer
        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        auctions.offer{value: 1 ether}(1);

        // 2nd offer to include delta
        vm.deal(address(bob), 0.09 ether);
        vm.prank(address(bob));
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP8Auctions.InsufficientOfferAmount.selector, 1, address(bob), 1.1 ether, 1.09 ether
            )
        );
        auctions.offer{value: 0.09 ether}(1);
    }

    function test_OfferExtendsEndTime() public {
        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.prank(owner);
        auctions.setMinBidDetlaPoints(10_000);

        // initial offer
        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        auctions.offer{value: 1 ether}(1);

        // 2nd offer to include delta
        vm.deal(address(bob), 0.09 ether);
        vm.prank(address(bob));
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP8Auctions.InsufficientOfferAmount.selector, 1, address(bob), 1.1 ether, 1.09 ether
            )
        );
        auctions.offer{value: 0.09 ether}(1);
    }

    function test_Settle() public {
        address marketplace = vm.addr(100);
        assertFalse(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        vm.prank(owner);
        auctions.grantRole(marketplace, MARKETPLACE_ROLE);
        assertTrue(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        auctions.offer{value: 1 ether}(1);

        vm.prank(marketplace);
        vm.expectEmit(address(auctions));
        emit Settled(1, address(alice), address(alice), tokenId, address(bob), 1 ether);
        auctions.settle(1);

        assertFalse(listings.isListed(1));
        assertFalse(listings.isActiveListing(1));
        assertFalse(auctions.isIssued(1));
        assertFalse(auctions.isActiveAuction(1));
        assertEq(0, address(bob).balance);
        assertEq(1 ether, address(marketplace).balance);
    }

    function test_Revert_SettleWhenNoBids() public {
        address marketplace = vm.addr(100);
        assertFalse(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        vm.prank(owner);
        auctions.grantRole(marketplace, MARKETPLACE_ROLE);
        assertTrue(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        bytes32 tokenId = bytes32(0);
        (UniversalProfile profile,) = deployProfile();
        asset.mint(address(profile), tokenId, false, "");

        vm.prank(address(profile));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.NotOffered.selector, 1, address(0)));
        auctions.settle(1);
    }

    function test_Revert_SettleWhenRetractedHighest() public {
        address marketplace = vm.addr(100);
        assertFalse(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        vm.prank(owner);
        auctions.grantRole(marketplace, MARKETPLACE_ROLE);
        assertTrue(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        auctions.offer{value: 1 ether}(1);

        vm.warp(block.timestamp + 7 days + 24 hours);
        vm.prank(address(bob));
        auctions.retract(1);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(LSP8Auctions.NotOffered.selector, 1, address(0)));
        auctions.settle(1);

        assertTrue(listings.isListed(1));
        assertTrue(listings.isActiveListing(1));
        assertTrue(auctions.isIssued(1));
        assertFalse(auctions.isActiveAuction(1));
        assertEq(1 ether, address(bob).balance);
        assertEq(0, address(marketplace).balance);
    }

    function test_RetractAfterAuctionCanceled() public {
        address marketplace = vm.addr(100);
        assertFalse(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        vm.prank(owner);
        auctions.grantRole(marketplace, MARKETPLACE_ROLE);
        assertTrue(auctions.hasRole(marketplace, MARKETPLACE_ROLE));

        bytes32 tokenId = bytes32(0);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        auctions.offer{value: 1 ether}(1);
        assertEq(0 ether, address(bob).balance);

        vm.prank(address(alice));
        auctions.cancel(1);

        vm.prank(address(bob));
        // vm.expectEmit(address(auctions));
        emit Retracted(1, address(bob), 1 ether);
        auctions.retract(1);
        assertEq(1 ether, address(bob).balance);
    }
}
