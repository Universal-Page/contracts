// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {_INTERFACEID_LSP0} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0Constants.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {Module, MARKETPLACE_ROLE} from "../../../src/marketplace/common/Module.sol";
import {Points} from "../../../src/common/Points.sol";
import {Royalties, RoyaltiesInfo} from "../../../src/common/Royalties.sol";
import {Base} from "../../../src/marketplace/common/Base.sol";
import {LSP8Listings} from "../../../src/marketplace/lsp8/LSP8Listings.sol";
import {LSP8Offers, CANCELATION_COOLDOWN} from "../../../src/marketplace/lsp8/LSP8Offers.sol";
import {LSP8Orders} from "../../../src/marketplace/lsp8/LSP8Orders.sol";
import {LSP8Auctions} from "../../../src/marketplace/lsp8/LSP8Auctions.sol";
import {LSP8Marketplace} from "../../../src/marketplace/lsp8/LSP8Marketplace.sol";
import {Participant, GENESIS_DISCOUNT} from "../../../src/marketplace/Participant.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP7DigitalAssetMock} from "../lsp7/LSP7DigitalAssetMock.sol";
import {LSP8DigitalAssetMock} from "./LSP8DigitalAssetMock.sol";

contract LSP8MarketplaceTest is Test {
    event FeePointsChanged(uint32 oldPoints, uint32 newPoints);
    event RoyaltiesThresholdPointsChanged(uint32 oldPoints, uint32 newPoints);
    event ValueWithdrawn(address indexed beneficiary, uint256 indexed value);
    event Sold(
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        bytes32 tokenId,
        uint256 totalPaid,
        uint256 totalFee,
        uint256 totalRoyalties,
        bytes data
    );
    event RoyalitiesPaidOut(
        address indexed asset, bytes32 tokenId, uint256 totalPaid, address indexed recipient, uint256 amount
    );

    LSP8Listings listings;
    LSP8Offers offers;
    LSP8Orders orders;
    LSP8Auctions auctions;
    LSP8Marketplace marketplace;
    Participant participant;
    address admin;
    address owner;
    address beneficiary;
    LSP8DigitalAssetMock asset;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);
        beneficiary = vm.addr(3);

        asset = new LSP8DigitalAssetMock("Mock", "MCK", owner, 0, 0);

        participant = Participant(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new Participant()),
                        admin,
                        abi.encodeWithSelector(Participant.initialize.selector, owner)
                    )
                )
            )
        );
        listings = LSP8Listings(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP8Listings()), admin, abi.encodeWithSelector(LSP8Listings.initialize.selector, owner)
                )
            )
        );
        offers = LSP8Offers(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP8Offers()),
                    admin,
                    abi.encodeWithSelector(LSP8Offers.initialize.selector, owner, listings)
                )
            )
        );
        orders = LSP8Orders(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP8Orders()), admin, abi.encodeWithSelector(LSP8Orders.initialize.selector, owner)
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
        marketplace = LSP8Marketplace(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new LSP8Marketplace()),
                        admin,
                        abi.encodeWithSelector(
                            LSP8Marketplace.initialize.selector,
                            owner,
                            beneficiary,
                            listings,
                            offers,
                            orders,
                            auctions,
                            participant
                        )
                    )
                )
            )
        );

        vm.startPrank(owner);
        listings.grantRole(address(marketplace), MARKETPLACE_ROLE);
        listings.grantRole(address(auctions), MARKETPLACE_ROLE);
        offers.grantRole(address(marketplace), MARKETPLACE_ROLE);
        orders.grantRole(address(marketplace), MARKETPLACE_ROLE);
        auctions.grantRole(address(marketplace), MARKETPLACE_ROLE);
        vm.stopPrank();

        assertTrue(listings.hasRole(address(marketplace), MARKETPLACE_ROLE));
        assertTrue(listings.hasRole(address(auctions), MARKETPLACE_ROLE));
        assertTrue(offers.hasRole(address(marketplace), MARKETPLACE_ROLE));
        assertTrue(orders.hasRole(address(marketplace), MARKETPLACE_ROLE));
        assertTrue(auctions.hasRole(address(marketplace), MARKETPLACE_ROLE));
    }

    function test_Initialized() public {
        assertTrue(!marketplace.paused());
        assertEq(owner, marketplace.owner());
        assertEq(beneficiary, marketplace.beneficiary());
        assertEq(address(listings), address(marketplace.listings()));
        assertEq(address(offers), address(marketplace.offers()));
        assertEq(address(orders), address(marketplace.orders()));
        assertEq(address(auctions), address(marketplace.auctions()));
        assertEq(address(participant), address(marketplace.participant()));
        assertEq(0, marketplace.feePoints());
        assertEq(0, marketplace.royaltiesThresholdPoints());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        marketplace.pause();
        marketplace.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        marketplace.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        marketplace.unpause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        marketplace.setFeePoints(0);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        marketplace.setRoyaltiesThresholdPoints(0);
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        marketplace.pause();
        vm.expectRevert("Pausable: paused");
        marketplace.buy(1, address(100));
        vm.expectRevert("Pausable: paused");
        marketplace.acceptOffer(1, address(100));
        vm.expectRevert("Pausable: paused");
        marketplace.acceptHighestBid(1);
    }

    function test_FeePoints() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit FeePointsChanged(0, 100_000);
        marketplace.setFeePoints(100_000);
    }

    function test_RoyaltiesThresholdPoints() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit RoyaltiesThresholdPointsChanged(0, 100_000);
        marketplace.setRoyaltiesThresholdPoints(100_000);
    }

    function testFuzz_Buy(uint256 price) public {
        vm.assume(price <= 1_000_000_000 ether);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, price, block.timestamp, 10 days);

        vm.deal(address(bob), price);
        vm.prank(address(bob));
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            tokenId,
            price,
            0,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.buy{value: price}(1, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(alice).balance, price);
        assertEq(address(bob).balance, 0);
        assertEq(asset.tokenOwnerOf(tokenId), address(bob));
    }

    function testFuzz_BuyWithFee(uint256 price, uint32 feePoints) public {
        vm.assume(price <= 1_000_000_000 ether);
        vm.assume(Points.isValid(feePoints));

        vm.prank(owner);
        marketplace.setFeePoints(feePoints);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, price, block.timestamp, 10 days);

        uint256 feeAmount = Points.realize(price, feePoints);
        vm.deal(address(bob), price);

        vm.prank(address(bob));
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            tokenId,
            price,
            feeAmount,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.buy{value: price}(1, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, feeAmount);
        assertEq(address(alice).balance, price - feeAmount);
        assertEq(address(bob).balance, 0);
        assertEq(asset.tokenOwnerOf(tokenId), address(bob));
    }

    function test_BuyWithDiscount() public {
        LSP7DigitalAssetMock discountAsset = new LSP7DigitalAssetMock("Discount", "DSC", owner, 0, true);
        vm.prank(owner);
        participant.setGenesisAsset(discountAsset);

        vm.prank(owner);
        marketplace.setFeePoints(10_000);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        discountAsset.mint(address(alice), 1, false, "");

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");

        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        uint256 totalPrice = 1 ether;
        uint256 feeAmount = Points.realize(totalPrice, 10_000);
        uint256 discountFeeAmount = Points.realize(feeAmount, GENESIS_DISCOUNT);
        vm.deal(address(bob), totalPrice);

        vm.prank(address(bob));
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            tokenId,
            totalPrice,
            feeAmount - discountFeeAmount,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.buy{value: totalPrice}(1, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, feeAmount - discountFeeAmount);
        assertEq(address(alice).balance, totalPrice - (feeAmount - discountFeeAmount));
        assertEq(address(bob).balance, 0);
        assertEq(asset.tokenOwnerOf(tokenId), address(bob));
    }

    function testFuzz_BuyWithRoyalties(uint256 price, uint32 royaltiesPoints0, uint32 royaltiesPoints1) public {
        vm.assume(price <= 1_000_000_000 ether);
        vm.assume(Points.isValid(royaltiesPoints0));
        vm.assume(Points.isValid(royaltiesPoints1));
        vm.assume(royaltiesPoints0 <= Points.BASIS - royaltiesPoints1);

        address royaltiesRecipient0 = vm.addr(100);
        address royaltiesRecipient1 = vm.addr(101);

        vm.startPrank(owner);
        Royalties.setRoyalties(address(asset), RoyaltiesInfo(_INTERFACEID_LSP0, royaltiesRecipient0, royaltiesPoints0));
        Royalties.setRoyalties(address(asset), RoyaltiesInfo(_INTERFACEID_LSP0, royaltiesRecipient1, royaltiesPoints1));
        vm.stopPrank();

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, price, block.timestamp, 10 days);

        uint256 royaltiesAmount0 = Points.realize(price, royaltiesPoints0);
        uint256 royaltiesAmount1 = Points.realize(price, royaltiesPoints1);
        vm.deal(address(bob), price);

        vm.prank(address(bob));
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            tokenId,
            price,
            0,
            royaltiesAmount0 + royaltiesAmount1,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
        if (royaltiesAmount0 > 0) {
            vm.expectEmit(address(marketplace));
            emit RoyalitiesPaidOut(address(asset), tokenId, price, royaltiesRecipient0, royaltiesAmount0);
        }
        if (royaltiesAmount1 > 0) {
            vm.expectEmit(address(marketplace));
            emit RoyalitiesPaidOut(address(asset), tokenId, price, royaltiesRecipient1, royaltiesAmount1);
        }
        marketplace.buy{value: price}(1, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, 0);
        assertEq(address(alice).balance, price - royaltiesAmount0 - royaltiesAmount1);
        assertEq(address(bob).balance, 0);
        assertEq(address(royaltiesRecipient0).balance, royaltiesAmount0);
        assertEq(address(royaltiesRecipient1).balance, royaltiesAmount1);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.tokenOwnerOf(tokenId), address(bob));
    }

    function test_BuyAndWithdrawFee() public {
        vm.prank(owner);
        marketplace.setFeePoints(10_000);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            tokenId,
            1 ether,
            0.1 ether,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.buy{value: 1 ether}(1, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, 0.1 ether);
        assertEq(address(alice).balance, 0.9 ether);
        assertEq(address(bob).balance, 0);
        assertEq(asset.tokenOwnerOf(tokenId), address(bob));

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit ValueWithdrawn(beneficiary, 0.07 ether);
        marketplace.withdraw(0.07 ether);

        assertEq(address(marketplace).balance, 0.03 ether);
        assertEq(address(beneficiary).balance, 0.07 ether);
    }

    function testFuzz_Revert_BuyIfRoyltiesExceedThreshold() public {
        vm.startPrank(owner);
        marketplace.setRoyaltiesThresholdPoints(1);
        Royalties.setRoyalties(address(asset), RoyaltiesInfo(_INTERFACEID_LSP0, address(100), 2));
        vm.stopPrank();

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        vm.expectRevert(
            abi.encodeWithSelector(Base.RoyaltiesExceedThreshold.selector, 1, 1 ether, Points.realize(1 ether, 2))
        );
        marketplace.buy{value: 1 ether}(1, address(bob));
    }

    function testFuzz_AcceptOffer(uint256 price, uint256 totalPrice) public {
        vm.assume(price <= 1_000_000_000 ether);
        vm.assume(totalPrice <= 1_000_000_000 ether);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, price, block.timestamp, 10 days);

        vm.deal(address(bob), totalPrice);
        vm.prank(address(bob));
        offers.place{value: totalPrice}(1, totalPrice, 1 hours);

        vm.prank(address(alice));
        vm.expectEmit(address(marketplace));
        // emit Sale(1, address(asset), tokenId, address(alice), address(bob), totalPrice);
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            tokenId,
            totalPrice,
            0,
            0,
            hex"010000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.acceptOffer(1, address(bob));

        assertFalse(listings.isListed(1));
        assertFalse(offers.isPlacedOffer(1, address(alice)));
        assertEq(address(alice).balance, totalPrice);
        assertEq(address(bob).balance, 0);
        assertEq(asset.tokenOwnerOf(tokenId), address(bob));
    }

    // function testFuzz_AcceptHighestBid(uint256 startPrice, uint256 bidPrice) public {
    //     vm.assume(startPrice <= 1_000_000_000 ether);
    //     vm.assume(bidPrice >= startPrice && bidPrice <= 1_000_000_000 ether);

    //     (UniversalProfile alice,) = deployProfile();
    //     (UniversalProfile bob,) = deployProfile();

    //     bytes32 tokenId = bytes32(0);
    //     asset.mint(address(alice), tokenId, false, "");
    //     vm.prank(address(alice));
    //     asset.authorizeOperator(address(marketplace), tokenId, "");
    //     vm.prank(address(alice));
    //     auctions.issue(address(asset), tokenId, startPrice, block.timestamp, 7 days);

    //     vm.deal(address(bob), bidPrice);
    //     vm.prank(address(bob));
    //     auctions.offer{value: bidPrice}(1);

    //     vm.prank(address(alice));
    //     vm.expectEmit(address(marketplace));
    //     emit Sale(1, address(asset), tokenId, address(alice), address(bob), bidPrice);
    //     marketplace.acceptHighestBid(1);

    //     assertFalse(listings.isListed(1));
    //     assertFalse(auctions.isIssued(1));
    //     assertEq(address(alice).balance, bidPrice);
    //     assertEq(address(bob).balance, 0);
    //     assertEq(asset.tokenOwnerOf(tokenId), address(bob));
    // }

    // function test_Revert_AcceptHighestBidIfNotSeller() public {
    //     (UniversalProfile alice,) = deployProfile();
    //     (UniversalProfile bob,) = deployProfile();

    //     bytes32 tokenId = bytes32(0);
    //     asset.mint(address(alice), tokenId, false, "");
    //     vm.prank(address(alice));
    //     asset.authorizeOperator(address(marketplace), tokenId, "");
    //     vm.prank(address(alice));
    //     auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

    //     vm.deal(address(bob), 1 ether);
    //     vm.prank(address(bob));
    //     auctions.offer{value: 1 ether}(1);

    //     vm.prank(address(100));
    //     vm.expectRevert(abi.encodeWithSelector(LSP8Marketplace.UnathorizedSeller.selector, address(100)));
    //     marketplace.acceptHighestBid(1);
    // }

    function test_Revert_BuyIfAuctioned() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LSP8Marketplace.Auctioned.selector, 1));
        marketplace.buy{value: 1 ether}(1, address(bob));
    }

    function test_Revert_AcceptOfferIfAuctioned() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        auctions.issue(address(asset), tokenId, 1 ether, block.timestamp, 7 days);

        vm.deal(address(bob), 1 ether);
        vm.prank(address(bob));
        offers.place(1, 0 ether, 1 hours);

        vm.prank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(LSP8Marketplace.Auctioned.selector, 1));
        marketplace.acceptOffer(1, address(bob));
    }

    function test_Revert_AcceptOfferIfFrontRan() public {
        uint256 initialTime = 3 hours;

        // advance block time
        vm.warp(initialTime);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 10 ether);
        vm.prank(address(bob));
        offers.place{value: 10 ether}(1, 10 ether, 1 hours);

        // cancel the offer and place a new one with a lower price
        vm.prank(address(bob));
        offers.cancel(1);

        vm.prank(address(bob));
        offers.place{value: 1 wei}(1, 1 wei, 1 hours);

        vm.prank(address(alice));
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP8Offers.RecentlyCanceled.selector, 1, address(bob), initialTime + CANCELATION_COOLDOWN
            )
        );
        marketplace.acceptOffer(1, address(bob));

        assertTrue(listings.isListed(1));
        assertTrue(offers.isPlacedOffer(1, address(bob)));
        assertEq(asset.tokenOwnerOf(tokenId), address(alice));
    }

    function testFuzz_AcceptOfferAfterCooldownCancellation() public {
        uint256 initialTime = 3 hours;

        // advance block time
        vm.warp(initialTime);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32 tokenId = bytes32(0);
        asset.mint(address(alice), tokenId, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), tokenId, "");
        vm.prank(address(alice));
        listings.list(address(asset), tokenId, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 10 ether);
        vm.prank(address(bob));
        offers.place{value: 10 ether}(1, 10 ether, 10 hours);

        // cancel the offer and place a new one with a lower price
        vm.prank(address(bob));
        offers.cancel(1);

        vm.prank(address(bob));
        offers.place{value: 1 ether}(1, 1 ether, 10 hours);

        // advance block time
        vm.warp(initialTime + CANCELATION_COOLDOWN);

        vm.prank(address(alice));
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            tokenId,
            1 ether,
            0,
            0,
            hex"010000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.acceptOffer(1, address(bob));

        assertFalse(listings.isListed(1));
        assertFalse(offers.isPlacedOffer(1, address(alice)));
        assertEq(address(alice).balance, 1 ether);
        assertEq(address(bob).balance, 9 ether);
        assertEq(asset.tokenOwnerOf(tokenId), address(bob));
    }

    function testFuzz_FillOrder(uint256 tokenCount) public {
        vm.assume(tokenCount > 0 && tokenCount < 100);

        uint256 tokenPrice = 1 ether;
        uint256 fillCount = Math.max(1, (tokenCount * 70) / 100);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32[] memory tokenIds = new bytes32[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = bytes32(i + 1);

            asset.mint(address(bob), tokenIds[i], false, "");

            vm.prank(address(bob));
            asset.authorizeOperator(address(marketplace), tokenIds[i], "");
        }

        bytes32[] memory fillTokenIds = new bytes32[](fillCount);
        for (uint256 i = 0; i < fillCount; i++) {
            fillTokenIds[i] = tokenIds[i];
        }

        vm.deal(address(alice), tokenPrice * fillCount);
        vm.prank(address(alice));
        uint256 orderId =
            orders.place{value: tokenPrice * fillCount}(address(asset), tokenPrice, tokenIds, uint16(fillCount));
        assertEq(orderId, 1);

        assertEq(address(alice).balance, 0);
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), tokenCount);

        vm.prank(address(bob));
        for (uint256 i = 0; i < fillCount; i++) {
            vm.expectEmit(address(marketplace));
            emit Sold(
                address(asset),
                address(bob),
                address(alice),
                fillTokenIds[i],
                tokenPrice,
                0,
                0,
                hex"020000000000000000000000000000000000000000000000000000000000000001"
            );
        }
        marketplace.fillOrder(orderId, fillTokenIds);

        assertEq(address(alice).balance, 0);
        assertEq(address(bob).balance, tokenPrice * fillCount);
        assertEq(asset.balanceOf(address(alice)), fillCount);
        assertEq(asset.balanceOf(address(bob)), tokenCount - fillCount);
    }
}
