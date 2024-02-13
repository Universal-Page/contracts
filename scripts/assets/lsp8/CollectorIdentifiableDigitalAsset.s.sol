// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {LSP6KeyManager} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManager.sol";
import {OPERATION_0_CALL} from "@erc725/smart-contracts/contracts/constants.sol";
import {CollectorIdentifiableDigitalAsset} from "../../../src/assets/lsp8/CollectorIdentifiableDigitalAsset.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address profile = vm.envAddress("PROFILE_ADDRESS");
        address controller = vm.envAddress("COLLECTOR_CONTROLLER_ADDRESS");

        vm.broadcast(admin);
        CollectorIdentifiableDigitalAsset asset =
            new CollectorIdentifiableDigitalAsset("Universal Page Pro", "UPP", profile, controller, 1000);
        console.log(string.concat("CollectorIdentifiableDigitalAsset: deploy ", Strings.toHexString(address(asset))));
    }
}

contract Claim is Script {
    function run() external {
        address profileController = vm.envAddress("PROFILE_CONTROLLER_ADDRESS");
        UniversalProfile profile = UniversalProfile(payable(vm.envAddress("PROFILE_ADDRESS")));
        CollectorIdentifiableDigitalAsset asset =
            CollectorIdentifiableDigitalAsset(payable(vm.envAddress("CONTRACT_COLLECTOR_DIGITAL_ASSET_ADDRESS")));

        if (address(asset).balance > 0) {
            console.log(
                string.concat("CollectorIdentifiableDigitalAsset: withdraw ", Strings.toString(address(asset).balance)),
                "wei to",
                Strings.toHexString(asset.beneficiary())
            );
            vm.broadcast(profileController);
            profile.execute(
                OPERATION_0_CALL,
                address(asset),
                0,
                abi.encodeWithSelector(asset.withdraw.selector, address(asset).balance)
            );
        }
    }
}

contract Configure is Script {
    bytes32 private constant _LSP8_TOKEN_METADATA_BASE_URI_KEY =
        0x1a7628600c3bac7101f53697f48df381ddc36b9015e7d7c9c5633d1252aa2843;

    bytes4 private constant _baseUriHash = bytes4(bytes32(keccak256("keccak256(utf8)")));

    function run() external {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address assetController = vm.envAddress("COLLECTOR_CONTROLLER_ADDRESS");
        address profileController = vm.envAddress("PROFILE_CONTROLLER_ADDRESS");
        UniversalProfile profile = UniversalProfile(payable(vm.envAddress("PROFILE_ADDRESS")));
        CollectorIdentifiableDigitalAsset asset =
            CollectorIdentifiableDigitalAsset(payable(vm.envAddress("CONTRACT_COLLECTOR_DIGITAL_ASSET_ADDRESS")));

        bytes memory currentBaseUri = asset.getData(_LSP8_TOKEN_METADATA_BASE_URI_KEY);
        string memory baseUri = vm.envString("COLLECTOR_DIGITAL_ASSET_BASE_URI");
        bytes memory encodedBaseUri = bytes.concat(_baseUriHash, bytes(baseUri));
        if (keccak256(encodedBaseUri) != keccak256(currentBaseUri)) {
            vm.broadcast(profileController);
            profile.execute(
                OPERATION_0_CALL,
                address(asset),
                0,
                abi.encodeWithSelector(asset.setData.selector, _LSP8_TOKEN_METADATA_BASE_URI_KEY, encodedBaseUri)
            );
            console.log(string.concat("CollectorIdentifiableDigitalAsset: setBaseUri ", baseUri));
        }

        if (asset.controller() != assetController) {
            vm.broadcast(profileController);
            profile.execute(
                OPERATION_0_CALL,
                address(asset),
                0,
                abi.encodeWithSelector(asset.setController.selector, assetController)
            );
            console.log(
                string.concat("CollectorIdentifiableDigitalAsset: setController ", Strings.toHexString(assetController))
            );
        }

        if (asset.beneficiary() != treasury) {
            vm.broadcast(profileController);
            profile.execute(
                OPERATION_0_CALL, address(asset), 0, abi.encodeWithSelector(asset.setBeneficiary.selector, treasury)
            );
            console.log(
                string.concat("CollectorIdentifiableDigitalAsset: setBeneficiary ", Strings.toHexString(treasury))
            );
        }
    }
}
