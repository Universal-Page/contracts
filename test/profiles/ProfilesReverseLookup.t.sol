// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {LSP6KeyManager} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManager.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {LSP6Utils} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Utils.sol";
import {ALL_REGULAR_PERMISSIONS} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Constants.sol";
import {deployProfile} from "../utils/profile.sol";
import {ProfilesReverseLookup} from "../../src/profiles/ProfilesReverseLookup.sol";

contract ProfilesReverseLookupTest is Test {
    event ProfileRegistered(address indexed controller, address indexed profile, bytes data);
    event ProfileUnregistered(address indexed controller, address indexed profile, bytes data);

    ProfilesReverseLookup lookup;
    address controller;

    function setUp() public {
        controller = vm.addr(1);

        lookup = new ProfilesReverseLookup();
    }

    function test_Register() public {
        (UniversalProfile alice, LSP6KeyManager keyManager) = deployProfile();

        (bytes32[] memory keys, bytes[] memory values) =
            LSP6Utils.generateNewPermissionsKeys(alice, controller, ALL_REGULAR_PERMISSIONS);
        vm.prank(address(keyManager));
        alice.setDataBatch(keys, values);

        assertEq(new address[](0), lookup.profilesOf(controller));
        assertFalse(lookup.registered(controller, address(alice)));

        vm.prank(controller);
        vm.expectEmit();
        emit ProfileRegistered(controller, address(alice), "0x");
        lookup.register(controller, address(alice), "0x");

        assertEq(lookup.profilesOf(controller).length, 1);
        assertEq(lookup.profilesOf(controller)[0], address(alice));
        assertTrue(lookup.registered(controller, address(alice)));
    }

    function test_Revert_NotController() public {
        (UniversalProfile alice,) = deployProfile();

        vm.prank(controller);
        vm.expectRevert(
            abi.encodeWithSelector(ProfilesReverseLookup.UnathorizedController.selector, controller, address(alice))
        );
        lookup.register(controller, address(alice), "0x");
    }

    function test_Revert_AlreadyRegistered() public {
        (UniversalProfile alice, LSP6KeyManager keyManager) = deployProfile();

        (bytes32[] memory keys, bytes[] memory values) =
            LSP6Utils.generateNewPermissionsKeys(alice, controller, ALL_REGULAR_PERMISSIONS);
        vm.prank(address(keyManager));
        alice.setDataBatch(keys, values);

        vm.prank(controller);
        lookup.register(controller, address(alice), "0x");

        vm.prank(controller);
        vm.expectRevert(
            abi.encodeWithSelector(ProfilesReverseLookup.AlreadyRegistered.selector, controller, address(alice))
        );
        lookup.register(controller, address(alice), "0x");
    }

    function test_UnregisterAsController() public {
        (UniversalProfile alice, LSP6KeyManager keyManager) = deployProfile();

        (bytes32[] memory keys, bytes[] memory values) =
            LSP6Utils.generateNewPermissionsKeys(alice, controller, ALL_REGULAR_PERMISSIONS);
        vm.prank(address(keyManager));
        alice.setDataBatch(keys, values);

        vm.prank(controller);
        vm.expectEmit();
        emit ProfileRegistered(controller, address(alice), "0x");
        lookup.register(controller, address(alice), "0x");

        assertEq(lookup.profilesOf(controller).length, 1);
        assertEq(lookup.profilesOf(controller)[0], address(alice));
        assertTrue(lookup.registered(controller, address(alice)));

        vm.prank(controller);
        vm.expectEmit();
        emit ProfileUnregistered(controller, address(alice), "0x");
        lookup.unregister(controller, address(alice), "0x");

        assertEq(lookup.profilesOf(controller).length, 0);
        assertFalse(lookup.registered(controller, address(alice)));
    }

    function test_UnregisterAsProfile() public {
        (UniversalProfile alice, LSP6KeyManager keyManager) = deployProfile();

        (bytes32[] memory keys, bytes[] memory values) =
            LSP6Utils.generateNewPermissionsKeys(alice, controller, ALL_REGULAR_PERMISSIONS);
        vm.prank(address(keyManager));
        alice.setDataBatch(keys, values);

        vm.prank(controller);
        vm.expectEmit();
        emit ProfileRegistered(controller, address(alice), "0x");
        lookup.register(controller, address(alice), "0x");

        assertEq(lookup.profilesOf(controller).length, 1);
        assertEq(lookup.profilesOf(controller)[0], address(alice));
        assertTrue(lookup.registered(controller, address(alice)));

        vm.prank(address(alice));
        vm.expectEmit();
        emit ProfileUnregistered(controller, address(alice), "0x");
        lookup.unregister(controller, address(alice), "0x");

        assertEq(lookup.profilesOf(controller).length, 0);
        assertFalse(lookup.registered(controller, address(alice)));
    }

    function test_Revert_UnregisterNotController() public {
        (UniversalProfile alice,) = deployProfile();

        address pranker = vm.addr(2);

        vm.prank(pranker);
        vm.expectRevert(abi.encodeWithSelector(ProfilesReverseLookup.Unathorized.selector));
        lookup.unregister(controller, address(alice), "0x");
    }
}
