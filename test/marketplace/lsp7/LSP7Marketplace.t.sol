// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {_INTERFACEID_LSP0} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0Constants.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {Module, MARKETPLACE_ROLE} from "../../../src/marketplace/common/Module.sol";
import {Points} from "../../../src/common/Points.sol";
import {Royalties, RoyaltiesInfo} from "../../../src/common/Royalties.sol";
import {Base} from "../../../src/marketplace/common/Base.sol";
import {LSP7Listings} from "../../../src/marketplace/lsp7/LSP7Listings.sol";
import {LSP7Offers} from "../../../src/marketplace/lsp7/LSP7Offers.sol";
import {LSP7Marketplace} from "../../../src/marketplace/lsp7/LSP7Marketplace.sol";
import {Participant, GENESIS_DISCOUNT} from "../../../src/marketplace/Participant.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP7DigitalAssetMock} from "./LSP7DigitalAssetMock.sol";

contract LSP7MarketplaceTest is Test {
    event FeePointsChanged(uint32 oldPoints, uint32 newPoints);
    event RoyaltiesThresholdPointsChanged(uint32 oldPoints, uint32 newPoints);
    event Sale(
        uint256 indexed listingId,
        address indexed asset,
        uint256 itemCount,
        address indexed seller,
        address buyer,
        uint256 totalPaid
    );
    event RoyaltiesPaid(
        uint256 indexed listingId, address indexed asset, uint256 itemCount, address indexed recipient, uint256 amount
    );
    event FeePaid(uint256 indexed listingId, address indexed asset, uint256 itemCount, uint256 amount);
    event ValueWithdrawn(address indexed beneficiary, uint256 indexed value);

    LSP7Listings listings;
    LSP7Offers offers;
    LSP7Marketplace marketplace;
    Participant participant;
    address admin;
    address owner;
    address beneficiary;
    LSP7DigitalAssetMock asset;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);
        beneficiary = vm.addr(3);

        asset = new LSP7DigitalAssetMock("Mock", "MCK", owner, true);

        participant = Participant(
            payable(
                address(
                    new TransparentUpgradeableProxy(address(new Participant()), admin, abi.encodeWithSelector(
                        Participant.initialize.selector,
                        owner
                    ))
                )
            )
        );
        listings = LSP7Listings(
            address(
                new TransparentUpgradeableProxy(address(new LSP7Listings()), admin, abi.encodeWithSelector(LSP7Listings.initialize.selector, owner))
            )
        );
        offers = LSP7Offers(
            address(
                new TransparentUpgradeableProxy(address(new LSP7Offers()), admin, abi.encodeWithSelector(LSP7Offers.initialize.selector, owner, listings))
            )
        );
        marketplace = LSP7Marketplace(
            payable(
                address(
                    new TransparentUpgradeableProxy(address(new LSP7Marketplace()), admin, abi.encodeWithSelector(LSP7Marketplace.initialize.selector, owner, beneficiary, listings, offers, participant))
                )
            )
        );

        vm.startPrank(owner);
        listings.grantRole(address(marketplace), MARKETPLACE_ROLE);
        offers.grantRole(address(marketplace), MARKETPLACE_ROLE);
        vm.stopPrank();

        assertTrue(listings.hasRole(address(marketplace), MARKETPLACE_ROLE));
        assertTrue(offers.hasRole(address(marketplace), MARKETPLACE_ROLE));
    }

    function test_Initialized() public {
        assertTrue(!marketplace.paused());
        assertEq(owner, marketplace.owner());
        assertEq(beneficiary, marketplace.beneficiary());
        assertEq(address(listings), address(marketplace.listings()));
        assertEq(address(offers), address(marketplace.offers()));
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
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.pause();
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.unpause();
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setFeePoints(0);
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setRoyaltiesThresholdPoints(0);
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        marketplace.pause();
        vm.expectRevert("Pausable: paused");
        marketplace.buy(1, 1, address(100));
        vm.expectRevert("Pausable: paused");
        marketplace.acceptOffer(1, address(100));
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

    function testFuzz_Buy(uint256 itemCount, uint256 itemPrice) public {
        vm.assume(itemCount > 0 && itemCount <= 1e32);
        vm.assume(itemPrice <= 1_000_000_000 ether);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), itemCount, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), itemCount, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), itemCount, itemPrice, block.timestamp, 10 days);

        uint256 totalPrice = itemCount * itemPrice;
        vm.deal(address(bob), totalPrice);

        vm.prank(address(bob));
        vm.expectEmit(address(marketplace));
        emit Sale(1, address(asset), itemCount, address(alice), address(bob), totalPrice);
        marketplace.buy{value: totalPrice}(1, itemCount, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(alice).balance, totalPrice);
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), itemCount);
    }

    function testFuzz_BuyWithFee(uint256 itemCount, uint256 itemPrice, uint32 feePoints) public {
        vm.assume(itemCount > 0 && itemCount <= 1e32);
        vm.assume(itemPrice <= 1_000_000_000 ether);
        vm.assume(Points.isValid(feePoints));

        vm.prank(owner);
        marketplace.setFeePoints(feePoints);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), itemCount, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), itemCount, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), itemCount, itemPrice, block.timestamp, 10 days);

        uint256 totalPrice = itemCount * itemPrice;
        uint256 feeAmount = Points.realize(totalPrice, feePoints);
        vm.deal(address(bob), totalPrice);

        vm.prank(address(bob));
        if (feeAmount > 0) {
            vm.expectEmit(address(marketplace));
            emit FeePaid(1, address(asset), itemCount, feeAmount);
        }
        vm.expectEmit(address(marketplace));
        emit Sale(1, address(asset), itemCount, address(alice), address(bob), totalPrice);
        marketplace.buy{value: totalPrice}(1, itemCount, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, feeAmount);
        assertEq(address(alice).balance, totalPrice - feeAmount);
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), itemCount);
    }

    function test_BuyWithDiscount() public {
        LSP7DigitalAssetMock discountAsset = new LSP7DigitalAssetMock("Discount", "DSC", owner, true);
        vm.prank(owner);
        participant.setGenesisAsset(discountAsset);

        vm.prank(owner);
        marketplace.setFeePoints(10_000);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        discountAsset.mint(address(alice), 1, false, "");
        asset.mint(address(alice), 10, false, "");

        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), 10, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        uint256 totalPrice = 1 ether * 10;
        uint256 feeAmount = Points.realize(totalPrice, 10_000);
        uint256 discountFeeAmount = Points.realize(feeAmount, GENESIS_DISCOUNT);
        vm.deal(address(bob), totalPrice);

        vm.prank(address(bob));
        if (feeAmount > 0) {
            vm.expectEmit(address(marketplace));
            emit FeePaid(1, address(asset), 10, feeAmount - discountFeeAmount);
        }
        vm.expectEmit(address(marketplace));
        emit Sale(1, address(asset), 10, address(alice), address(bob), totalPrice);
        marketplace.buy{value: totalPrice}(1, 10, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, feeAmount - discountFeeAmount);
        assertEq(address(alice).balance, totalPrice - (feeAmount - discountFeeAmount));
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), 10);
    }

    function testFuzz_BuyWithRoyalties(
        uint256 itemCount,
        uint256 itemPrice,
        uint32 royaltiesPoints0,
        uint32 royaltiesPoints1
    ) public {
        vm.assume(itemCount > 0 && itemCount <= 1e32);
        vm.assume(itemPrice <= 1_000_000_000 ether);
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

        asset.mint(address(alice), itemCount, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), itemCount, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), itemCount, itemPrice, block.timestamp, 10 days);

        uint256 totalPrice = itemCount * itemPrice;
        uint256 royaltiesAmount0 = Points.realize(totalPrice, royaltiesPoints0);
        uint256 royaltiesAmount1 = Points.realize(totalPrice, royaltiesPoints1);
        vm.deal(address(bob), totalPrice);

        vm.prank(address(bob));
        if (royaltiesAmount0 > 0) {
            vm.expectEmit(address(marketplace));
            emit RoyaltiesPaid(1, address(asset), itemCount, royaltiesRecipient0, royaltiesAmount0);
        }
        if (royaltiesAmount1 > 0) {
            vm.expectEmit(address(marketplace));
            emit RoyaltiesPaid(1, address(asset), itemCount, royaltiesRecipient1, royaltiesAmount1);
        }
        vm.expectEmit(address(marketplace));
        emit Sale(1, address(asset), itemCount, address(alice), address(bob), totalPrice);
        marketplace.buy{value: totalPrice}(1, itemCount, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, 0);
        assertEq(address(alice).balance, totalPrice - royaltiesAmount0 - royaltiesAmount1);
        assertEq(address(bob).balance, 0);
        assertEq(address(royaltiesRecipient0).balance, royaltiesAmount0);
        assertEq(address(royaltiesRecipient1).balance, royaltiesAmount1);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), itemCount);
    }

    function test_BuyAndWithdrawFee() public {
        vm.prank(owner);
        marketplace.setFeePoints(10_000);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), 10, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 10 ether);
        vm.prank(address(bob));
        vm.expectEmit(address(marketplace));
        emit FeePaid(1, address(asset), 10, 1 ether);
        vm.expectEmit(address(marketplace));
        emit Sale(1, address(asset), 10, address(alice), address(bob), 10 ether);
        marketplace.buy{value: 10 ether}(1, 10, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, 1 ether);
        assertEq(address(alice).balance, 9 ether);
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), 10);

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit ValueWithdrawn(beneficiary, 0.7 ether);
        marketplace.withdraw(0.7 ether);

        assertEq(address(marketplace).balance, 0.3 ether);
        assertEq(address(beneficiary).balance, 0.7 ether);
    }

    function testFuzz_Revert_BuyIfRoyltiesExceedThreshold() public {
        vm.startPrank(owner);
        marketplace.setRoyaltiesThresholdPoints(1);
        Royalties.setRoyalties(address(asset), RoyaltiesInfo(_INTERFACEID_LSP0, address(100), 2));
        vm.stopPrank();

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), 10, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), 10, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), 10, 1 ether, block.timestamp, 10 days);

        vm.deal(address(bob), 10 ether);
        vm.prank(address(bob));
        vm.expectRevert(
            abi.encodeWithSelector(Base.RoyaltiesExceedThreshold.selector, 1, 10 ether, Points.realize(10 ether, 2))
        );
        marketplace.buy{value: 10 ether}(1, 10, address(bob));
    }

    function testFuzz_AcceptOffer(uint256 itemCount, uint256 itemPrice, uint256 totalPrice) public {
        vm.assume(itemCount > 0 && itemCount <= 1e32);
        vm.assume(itemPrice <= 1_000_000_000 ether);
        vm.assume(totalPrice <= 1_000_000_000 ether);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        asset.mint(address(alice), itemCount, false, "");
        vm.prank(address(alice));
        asset.authorizeOperator(address(marketplace), itemCount, "");
        vm.prank(address(alice));
        listings.list(address(asset), address(alice), itemCount, itemPrice, block.timestamp, 10 days);

        vm.deal(address(bob), totalPrice);
        vm.prank(address(bob));
        offers.place{value: totalPrice}(1, itemCount, 1 hours);

        vm.prank(address(alice));
        vm.expectEmit(address(marketplace));
        emit Sale(1, address(asset), itemCount, address(alice), address(bob), totalPrice);
        marketplace.acceptOffer(1, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(alice).balance, totalPrice);
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), itemCount);
    }
}
