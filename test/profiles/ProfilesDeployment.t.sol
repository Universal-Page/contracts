// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {LSP6KeyManagerInit} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManagerInit.sol";
import {LSP1UniversalReceiverDelegateUP} from
    "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1UniversalReceiverDelegateUP/LSP1UniversalReceiverDelegateUP.sol";
import {UniversalProfileInit} from "@lukso/lsp-smart-contracts/contracts/UniversalProfileInit.sol";
import {LSP23LinkedContractsFactory} from
    "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/LSP23LinkedContractsFactory.sol";
import {ILSP23LinkedContractsFactory} from
    "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/ILSP23LinkedContractsFactory.sol";
import {UniversalProfilePostDeploymentModule} from
    "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/modules/UniversalProfilePostDeploymentModule.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {LSP6Utils} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Utils.sol";
import {
    ALL_REGULAR_PERMISSIONS,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_REENTRANCY
} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Constants.sol";
import {LSP2Utils} from "@lukso/lsp-smart-contracts/contracts/LSP2ERC725YJSONSchema/LSP2Utils.sol";

contract ProfilesDeploymentTest is Test {
    function test_Replicate() public {
        LSP23LinkedContractsFactory factory = new LSP23LinkedContractsFactory();
        UniversalProfileInit profileInit = UniversalProfileInit(payable(0x52c90985AF970D4E0DC26Cb5D052505278aF32A9));
        LSP6KeyManagerInit keyManagerInit = LSP6KeyManagerInit(0xa75684d7D048704a2DB851D05Ba0c3cbe226264C);
        UniversalProfilePostDeploymentModule postDeploymentModule =
            UniversalProfilePostDeploymentModule(payable(0x000000000066093407b6704B89793beFfD0D8F00));
        LSP1UniversalReceiverDelegateUP universalReceiver =
            LSP1UniversalReceiverDelegateUP(0xA5467dfe7019bF2C7C5F7A707711B9d4cAD118c8);

        address controller = 0x6CACE3e8300F0Ff31896825B1e07e76B8cCc44D7;

        ILSP23LinkedContractsFactory.PrimaryContractDeploymentInit memory profileDeploymentData =
        ILSP23LinkedContractsFactory.PrimaryContractDeploymentInit({
            salt: hex"cd54accb45413d0e2558d8cb72125c0313038a1ccff82c70069f51a49188128b",
            fundingAmount: 0,
            implementationContract: 0x52c90985AF970D4E0DC26Cb5D052505278aF32A9,
            // initializationCalldata: abi.encodeWithSignature("initialize(address)", address(postDeploymentModule))
            initializationCalldata: hex"c4d66de8000000000000000000000000000000000066093407b6704b89793beffd0d8f00"
        });

        ILSP23LinkedContractsFactory.SecondaryContractDeploymentInit memory keyManagerDeploymentData =
        ILSP23LinkedContractsFactory.SecondaryContractDeploymentInit({
            fundingAmount: 0,
            implementationContract: 0xa75684d7D048704a2DB851D05Ba0c3cbe226264C,
            addPrimaryContractAddress: true,
            initializationCalldata: hex"c4d66de8",
            extraInitializationParams: hex""
        });

        // bytes32[] memory keys = new bytes32[](7);
        // keys[0] = LSP2Utils.generateSingletonKey("LSP1UniversalReceiverDelegate");
        // keys[1] = LSP2Utils.generateSingletonKey("LSP3Profile");
        // keys[2] = LSP2Utils.generateArrayKey("AddressPermissions[]");
        // keys[3] = LSP2Utils.generateArrayElementKeyAtIndex("AddressPermissions[]", 0);
        // keys[4] = LSP2Utils.generateMappingWithGroupingKey("AddressPermissions", "Permissions", controller);
        // keys[5] = LSP2Utils.generateArrayElementKeyAtIndex("AddressPermissions[]", 1);
        // keys[6] =
        //     LSP2Utils.generateMappingWithGroupingKey("AddressPermissions", "Permissions", address(universalReceiver));

        // bytes[] memory values = new bytes[](7);
        // values[0] = abi.encode(address(universalReceiver));
        // values[1] = "0x";
        // values[2] = abi.encode(uint128(2));
        // values[3] = abi.encode(controller);
        // values[4] = abi.encode(ALL_REGULAR_PERMISSIONS);
        // values[5] = abi.encode(address(universalReceiver));
        // values[6] = abi.encode(ALL_REGULAR_PERMISSIONS | _PERMISSION_SUPER_SETDATA | _PERMISSION_REENTRANCY);

        // bytes memory data = abi.encode(keys, values);

        bytes memory data =
            hex"0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000075ef83ad9559033e6e941db7d7c495acdce616347d28e90c7ce47cbfcfcad3bc50cfc51aec37c55a4d0b1a65c6255c4bf2fbdf6277f3cc0730c45b828b6db8b474b80742de2bf82acb3630000a5467dfe7019bf2c7c5f7a707711b9d4cad118c84b80742de2bf82acb36300006cace3e8300f0ff31896825b1e07e76b8ccc44d7df30dba06db6a30e65354d9a64c609861f089545ca58c6b4dbe31a5f338cb0e3df30dba06db6a30e65354d9a64c6098600000000000000000000000000000000df30dba06db6a30e65354d9a64c6098600000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000596f357c6ac93298c156efb4cfe5c5b87e140a9c5447f9b8a591b064db8201fc114e166edb697066733a2f2f516d53644744796978707338624570707671466e774e38384877574d4457464d4b356d4b5941575464624b546556000000000000000000000000000000000000000000000000000000000000000000000000000014a5467dfe7019bf2c7c5f7a707711b9d4cad118c800000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000060080000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000007f3f06000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014a5467dfe7019bf2c7c5f7a707711b9d4cad118c800000000000000000000000000000000000000000000000000000000000000000000000000000000000000146cace3e8300f0ff31896825b1e07e76b8ccc44d7000000000000000000000000";

        (address primaryContractAddress, address secondaryContractAddress) = factory.computeERC1167Addresses(
            profileDeploymentData, keyManagerDeploymentData, 0x000000000066093407b6704B89793beFfD0D8F00, data
        );

        assertEq(primaryContractAddress, 0x37Fa9FB05C2E3e9541a59B891321E9c4b8246442);
        assertEq(secondaryContractAddress, address(0));
    }
}
