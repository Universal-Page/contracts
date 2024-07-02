// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {_INTERFACEID_LSP0} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0Constants.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {Module, MARKETPLACE_ROLE} from "../../../src/marketplace/common/Module.sol";
import {Points} from "../../../src/common/Points.sol";
import {Royalties, RoyaltiesInfo} from "../../../src/common/Royalties.sol";
import {Base} from "../../../src/marketplace/common/Base.sol";
import {LSP7Listings} from "../../../src/marketplace/lsp7/LSP7Listings.sol";
import {LSP7Orders} from "../../../src/marketplace/lsp7/LSP7Orders.sol";
import {LSP7Marketplace} from "../../../src/marketplace/lsp7/LSP7Marketplace.sol";
import {Participant, GENESIS_DISCOUNT} from "../../../src/marketplace/Participant.sol";
import {deployProfile} from "../../utils/profile.sol";
import {LSP7DigitalAssetMock} from "./LSP7DigitalAssetMock.sol";

contract LSP7MarketplaceTest is Test {
    event FeePointsChanged(uint32 oldPoints, uint32 newPoints);
    event RoyaltiesThresholdPointsChanged(uint32 oldPoints, uint32 newPoints);
    event Sold(
        address indexed asset,
        address indexed seller,
        address indexed buyer,
        uint256 itemCount,
        uint256 totalPaid,
        uint256 totalFee,
        uint256 totalRoyalties,
        bytes data
    );
    event RoyaltiesPaidOut(
        address indexed asset, uint256 itemCount, uint256 totalPaid, address indexed recipient, uint256 amount
    );
    event ValueWithdrawn(address indexed beneficiary, uint256 indexed value);

    LSP7Listings listings;
    LSP7Orders orders;
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

        asset = new LSP7DigitalAssetMock("Mock", "MCK", owner, _LSP4_TOKEN_TYPE_NFT, true);

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
        listings = LSP7Listings(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP7Listings()), admin, abi.encodeWithSelector(LSP7Listings.initialize.selector, owner)
                )
            )
        );
        orders = LSP7Orders(
            address(
                new TransparentUpgradeableProxy(
                    address(new LSP7Orders()),
                    admin,
                    abi.encodeWithSelector(LSP7Orders.initialize.selector, owner)
                )
            )
        );
        marketplace = LSP7Marketplace(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new LSP7Marketplace()),
                        admin,
                        abi.encodeWithSelector(
                            LSP7Marketplace.initialize.selector, owner, beneficiary, listings, orders, participant
                        )
                    )
                )
            )
        );

        vm.startPrank(owner);
        listings.grantRole(address(marketplace), MARKETPLACE_ROLE);
        orders.grantRole(address(marketplace), MARKETPLACE_ROLE);
        vm.stopPrank();

        assertTrue(listings.hasRole(address(marketplace), MARKETPLACE_ROLE));
        assertTrue(orders.hasRole(address(marketplace), MARKETPLACE_ROLE));
    }

    function test_Initialized() public {
        assertTrue(!marketplace.paused());
        assertEq(owner, marketplace.owner());
        assertEq(beneficiary, marketplace.beneficiary());
        assertEq(address(listings), address(marketplace.listings()));
        assertEq(address(orders), address(marketplace.orders()));
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
        marketplace.buy(1, 1, address(100));
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
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            itemCount,
            totalPrice,
            0,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
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
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            itemCount,
            totalPrice,
            feeAmount,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.buy{value: totalPrice}(1, itemCount, address(bob));

        assertFalse(listings.isListed(1));
        assertEq(address(marketplace).balance, feeAmount);
        assertEq(address(alice).balance, totalPrice - feeAmount);
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), itemCount);
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
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            10,
            totalPrice,
            feeAmount - discountFeeAmount,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
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
        vm.expectEmit(address(marketplace));
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            itemCount,
            totalPrice,
            0,
            royaltiesAmount0 + royaltiesAmount1,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
        if (royaltiesAmount0 > 0) {
            vm.expectEmit(address(marketplace));
            emit RoyaltiesPaidOut(address(asset), itemCount, totalPrice, royaltiesRecipient0, royaltiesAmount0);
        }
        if (royaltiesAmount1 > 0) {
            vm.expectEmit(address(marketplace));
            emit RoyaltiesPaidOut(address(asset), itemCount, totalPrice, royaltiesRecipient1, royaltiesAmount1);
        }
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
        emit Sold(
            address(asset),
            address(alice),
            address(bob),
            10,
            10 ether,
            1 ether,
            0,
            hex"000000000000000000000000000000000000000000000000000000000000000001"
        );
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

    function testFuzz_FillOrder(uint256 itemCount, uint256 itemPrice, uint256 fillCount) public {
        vm.assume(itemPrice < 100_000_000 ether);
        vm.assume(itemCount > 0 && itemCount < 1_000_000);
        vm.assume(fillCount > 0 && fillCount < itemCount);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        vm.deal(address(alice), itemPrice * itemCount);
        vm.prank(address(alice));
        uint256 orderId = orders.place{value: itemPrice * itemCount}(address(asset), itemPrice, itemCount);
        assertEq(orderId, 1);

        asset.mint(address(bob), itemCount, false, "");
        vm.prank(address(bob));
        asset.authorizeOperator(address(marketplace), itemCount, "");

        assertEq(address(alice).balance, 0);
        assertEq(address(bob).balance, 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), itemCount);

        vm.prank(address(bob));
        vm.expectEmit();
        emit Sold(
            address(asset),
            address(bob),
            address(alice),
            fillCount,
            itemPrice * fillCount,
            0,
            0,
            hex"020000000000000000000000000000000000000000000000000000000000000001"
        );
        marketplace.fillOrder(orderId, fillCount);

        assertEq(address(alice).balance, 0);
        assertEq(address(bob).balance, itemPrice * fillCount);
        assertEq(asset.balanceOf(address(alice)), fillCount);
        assertEq(asset.balanceOf(address(bob)), itemCount - fillCount);
    }
}
