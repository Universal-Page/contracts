// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {_LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY} from
    "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1Constants.sol";
import {LSP1UniversalReceiverDelegateUP} from
    "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1UniversalReceiverDelegateUP/LSP1UniversalReceiverDelegateUP.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {LSP0ERC725AccountCore} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725AccountCore.sol";
import {OPERATION_0_CALL} from "@erc725/smart-contracts/contracts/constants.sol";
import {LSP6KeyManager} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManager.sol";
import {LSP6Utils} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Utils.sol";
// import {ALL_REGULAR_PERMISSIONS} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Constants.sol";
// import {ERC725} from "@erc725/smart-contracts/contracts/ERC725.sol";
import {LSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAsset.sol";
import {LSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {LSP2Utils} from "@lukso/lsp-smart-contracts/contracts/LSP2ERC725YJSONSchema/LSP2Utils.sol";
import {
    _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
    _PERMISSION_REENTRANCY,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_DELEGATECALL,
    _PERMISSION_SUPER_DELEGATECALL,
    ALL_REGULAR_PERMISSIONS,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY
} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Constants.sol";
import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";

contract Playground is Script {
    function run() external {
        address controller = vm.envAddress("PROFILE_CONTROLLER_ADDRESS");
        UniversalProfile profile = UniversalProfile(payable(vm.envAddress("PROFILE_ADDRESS")));

        vm.startBroadcast(controller);

        // (bytes32[] memory keys, bytes[] memory values) = LSP6Utils.generateNewPermissionsKeys(
        //     profile, 0x3f329Ebe23A6443BEBaf05C092C152a7754f5D32, ALL_REGULAR_PERMISSIONS
        // );

        // {
        //     address newController = ...;
        //     bytes32 permissions = ALL_REGULAR_PERMISSIONS;

        //     bytes32[] memory keys = new bytes32[](3);
        //     bytes[] memory values = new bytes[](3);

        //     uint128 arrayLength = uint128(bytes16(profile.getData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY)));
        //     uint128 newArrayLength = arrayLength + 1;

        //     keys[0] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        //     values[0] = abi.encodePacked(newArrayLength);

        //     keys[1] = LSP2Utils.generateArrayElementKeyAtIndex(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, arrayLength);
        //     values[1] = abi.encodePacked(newController);

        //     keys[2] = LSP2Utils.generateMappingWithGroupingKey(
        //         _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, bytes20(newController)
        //     );
        //     values[2] = abi.encodePacked(permissions);

        //     profile.setDataBatch(keys, values);
        // }

        // if (profileAddress == address(0)) {
        //     (UniversalProfile profile, LSP6KeyManager keyManager) = deployProfile(owner);
        //     console.log("Profile deployed at: %s", Strings.toHexString(uint160(address(profile)), 20));
        //     console.log("KeyManager deployed at: %s", Strings.toHexString(uint160(address(keyManager)), 20));
        //     profileAddress = address(profile);
        // }

        // vm.stopBroadcast();

        // address oldProfile = 0xd78A3A4A4cd3E01Cc6Af8f5Eb4acBc1049Fe315e;

        // (bytes32[] memory keys, bytes[] memory values) = LSP6Utils.generateNewPermissionsKeys(
        //     ERC725(address(profile)), 0x215331b6bbEb33a9C59c9Cfd0B49808516B2FecC, ALL_REGULAR_PERMISSIONS
        // );
        // vm.broadcast(controller);
        // LSP6Utils.setDataViaKeyManager(address(keyManager), keys, values);

        // uint256 ownerKey = 0xc0a4cb4f7926b36535ffa6aedc89414216ba5fb84f6c652ad9b6dc6c201924be;
        // address owner = vm.addr(ownerKey);
        // console.log("Owner: %s", Strings.toHexString(uint160(owner), 20));

        // vm.startBroadcast(ownerKey);

        // (UniversalProfile profile,) = deployProfile(owner);
        // console.log("Profile deployed at: %s", Strings.toHexString(uint160(address(profile)), 20));
        // UniversalProfile profile = UniversalProfile(payable(0x30B3f161Ee7A6b5E449cB5Ad4eeABEFcd8288362));

        // {
        //     address controller = 0xFDf3c3d1300E267E7405522cb374aef5d15d6a70;
        //     (bytes32[] memory keys, bytes[] memory values) =
        //         LSP6Utils.generateNewPermissionsKeys(profile, controller, ALL_REGULAR_PERMISSIONS);
        //     profile.setDataBatch(keys, values);
        // }

        // LSP6KeyManager(UniversalProfile(payable(oldProfile)).owner()).execute(
        //     abi.encodeWithSelector(
        //         profile.execute.selector,
        //         OPERATION_0_CALL,
        //         0x2079096B83F52e9405aDaCf224f5178FC88336B6,
        //         0,
        //         abi.encodeWithSelector(OwnableUnset.transferOwnership.selector, address(profile))
        //     )
        // );

        // LSP7DigitalAsset asset = LSP7DigitalAsset(0xD9D361D12C5Ef48E6a0A4e0E331d036C1720eFed);
        // console.log("Balance: ", asset.balanceOf(oldProfile));
        // if (asset.balanceOf(oldProfile) > 0) {
        //     LSP6KeyManager(UniversalProfile(payable(oldProfile)).owner()).execute(
        //         abi.encodeWithSelector(
        //             profile.execute.selector,
        //             OPERATION_0_CALL,
        //             address(asset),
        //             0,
        //             abi.encodeWithSelector(
        //                 asset.transfer.selector, oldProfile, address(profile), asset.balanceOf(oldProfile), false, "0x"
        //             )
        //         )
        //     );
        // }

        // LSP8IdentifiableDigitalAsset asset = LSP8IdentifiableDigitalAsset(0x2079096B83F52e9405aDaCf224f5178FC88336B6);
        // LSP6KeyManager(UniversalProfile(payable(oldProfile)).owner()).execute(
        //     abi.encodeWithSelector(
        //         profile.execute.selector,
        //         OPERATION_0_CALL,
        //         address(asset),
        //         0,
        //         abi.encodeWithSelector(
        //             asset.transfer.selector,
        //             oldProfile,
        //             address(profile),
        //             0x0000000000000000000000000000000000000000000000000000000000000001,
        //             false,
        //             "0x"
        //         )
        //     )
        // );

        vm.stopBroadcast();
    }

    function deployProfile(address controller) private returns (UniversalProfile profile, LSP6KeyManager keyManager) {
        profile = new UniversalProfile(controller);
        keyManager = new LSP6KeyManager(address(profile));
        LSP1UniversalReceiverDelegateUP delegate = new LSP1UniversalReceiverDelegateUP();

        // setup default receiver delegate
        {
            bytes32[] memory permissionValues = new bytes32[](2);
            permissionValues[0] = _PERMISSION_REENTRANCY;
            permissionValues[1] = _PERMISSION_SUPER_SETDATA;
            bytes32 permissions = LSP6Utils.combinePermissions(permissionValues);
            (bytes32[] memory keys, bytes[] memory values) =
                LSP6Utils.generateNewPermissionsKeys(profile, address(delegate), permissions);
            profile.setDataBatch(keys, values);
            profile.setData(_LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY, bytes.concat(bytes20(address(delegate))));
        }

        // wtf?!
        {
            (bytes32[] memory keys, bytes[] memory values) =
                LSP6Utils.generateNewPermissionsKeys(profile, address(profile), ALL_REGULAR_PERMISSIONS);
            profile.setDataBatch(keys, values);
        }

        // setup controller
        {
            (bytes32[] memory keys, bytes[] memory values) =
                LSP6Utils.generateNewPermissionsKeys(profile, controller, ALL_REGULAR_PERMISSIONS);
            profile.setDataBatch(keys, values);
        }

        // setup ownership chain
        profile.transferOwnership(address(keyManager));

        keyManager.execute(abi.encodeWithSelector(LSP0ERC725AccountCore.acceptOwnership.selector));
    }
}
