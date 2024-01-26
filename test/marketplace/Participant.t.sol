// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {
    Participant,
    GENESIS_DISCOUNT,
    COLLECTOR_TIER_0_DISCOUNT,
    COLLECTOR_TIER_1_DISCOUNT,
    COLLECTOR_TIER_2_DISCOUNT,
    COLLECTOR_TIER_3_DISCOUNT
} from "../../src/marketplace/Participant.sol";
import {deployProfile} from "../utils/profile.sol";
import {LSP7DigitalAssetMock} from "./lsp7/LSP7DigitalAssetMock.sol";
import {ICollectorIdentifiableDigitalAsset} from "../../src/assets/lsp8/ICollectorIdentifiableDigitalAsset.sol";
import {CollectorIdentifiableDigitalAsset} from "../../src/assets/lsp8/CollectorIdentifiableDigitalAsset.sol";

contract ParticipantTest is Test {
    event AssetFeeDiscountChanged(address indexed asset, uint32 previousDiscountPoints, uint32 newDiscountPoints);

    Participant participant;
    address admin;
    address owner;
    address assetOwner;
    uint256 controllerKey;
    address controller;
    LSP7DigitalAssetMock genesisAsset;
    CollectorIdentifiableDigitalAsset collectorAsset;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);
        assetOwner = vm.addr(3);
        controllerKey = 4;
        controller = vm.addr(controllerKey);

        genesisAsset = new LSP7DigitalAssetMock("Mock", "MCK", assetOwner, 0, true);
        collectorAsset =
            new CollectorIdentifiableDigitalAsset("Universal Page Collector", "UPC", assetOwner, controller, 1000);

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
    }

    function test_Initialize() public {
        assertTrue(!participant.paused());
        assertEq(owner, participant.owner());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        participant.setCollectorAsset(ICollectorIdentifiableDigitalAsset(vm.addr(1)));
        participant.setGenesisAsset(ILSP7DigitalAsset(vm.addr(1)));
        participant.pause();
        participant.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        participant.setCollectorAsset(ICollectorIdentifiableDigitalAsset(vm.addr(1)));

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        participant.setGenesisAsset(ILSP7DigitalAsset(vm.addr(1)));

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        participant.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        participant.unpause();
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        participant.pause();
        vm.expectRevert("Pausable: paused");
        participant.feeDiscountFor(vm.addr(1));
    }

    function testFuzz_GenesisFeeDiscount(uint256 tokenCount) public {
        vm.assume(tokenCount > 0);

        (UniversalProfile profile,) = deployProfile();

        genesisAsset.mint(address(profile), tokenCount, false, "");
        assertEq(genesisAsset.balanceOf(address(profile)), tokenCount);

        assertEq(participant.feeDiscountFor(address(profile)), 0);

        vm.prank(owner);
        participant.setGenesisAsset(genesisAsset);

        assertEq(participant.feeDiscountFor(address(profile)), GENESIS_DISCOUNT);
    }

    function test_CollectorTierFeeDiscount() public {
        (UniversalProfile profile,) = deployProfile();

        vm.prank(owner);
        participant.setCollectorAsset(collectorAsset);

        for (uint256 i = 0; i < 4; i++) {
            bytes32[] memory tokenIds = new bytes32[](1);
            tokenIds[0] = bytes32(uint256(((i + 1) << 4) | i));

            bytes32 hash = keccak256(
                abi.encodePacked(address(collectorAsset), block.chainid, address(profile), tokenIds, uint256(0 ether))
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);

            vm.prank(address(profile));
            collectorAsset.purchase(address(profile), tokenIds, v, r, s);
            assertEq(collectorAsset.balanceOf(address(profile)), i + 1);

            uint32 discount = participant.feeDiscountFor(address(profile));
            if (i == 0) {
                assertEq(discount, COLLECTOR_TIER_0_DISCOUNT);
            } else if (i == 1) {
                assertEq(discount, COLLECTOR_TIER_1_DISCOUNT);
            } else if (i == 2) {
                assertEq(discount, COLLECTOR_TIER_2_DISCOUNT);
            } else if (i == 3) {
                assertEq(discount, COLLECTOR_TIER_3_DISCOUNT);
            }
        }
    }
}
