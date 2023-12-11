// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Vm} from "forge-std/Vm.sol";
import {_LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY} from
    "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1Constants.sol";
import {LSP1UniversalReceiverDelegateUP} from
    "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1UniversalReceiverDelegateUP/LSP1UniversalReceiverDelegateUP.sol";
import {
    _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
    _PERMISSION_REENTRANCY,
    _PERMISSION_SUPER_SETDATA
} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Constants.sol";
import {LSP6KeyManager} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManager.sol";
import {LSP6Utils} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Utils.sol";
import {LSP2Utils} from "@lukso/lsp-smart-contracts/contracts/LSP2ERC725YJSONSchema/LSP2Utils.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";

address constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

function deployProfile() returns (UniversalProfile profile, LSP6KeyManager keyManager) {
    address deployer = vm.addr(100);
    profile = new UniversalProfile(deployer);
    keyManager = new LSP6KeyManager(address(profile));

    vm.prank(deployer);
    profile.transferOwnership(address(keyManager));
    vm.prank(address(keyManager));
    profile.acceptOwnership();

    LSP1UniversalReceiverDelegateUP delegate = new LSP1UniversalReceiverDelegateUP();

    vm.startPrank(address(keyManager));
    profile.setData(_LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY, bytes.concat(bytes20(address(delegate))));
    {
        bytes32 key = LSP2Utils.generateMappingWithGroupingKey(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, bytes20(address(delegate))
        );
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = _PERMISSION_REENTRANCY;
        permissions[1] = _PERMISSION_SUPER_SETDATA;
        profile.setData(key, abi.encodePacked(LSP6Utils.combinePermissions(permissions)));
    }
    vm.stopPrank();
}
