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
        address owner = vm.envAddress("OWNER_ADDRESS");
        address controller = vm.envAddress("COLLECTOR_CONTROLLER_ADDRESS");

        vm.broadcast(admin);
        CollectorIdentifiableDigitalAsset asset =
            new CollectorIdentifiableDigitalAsset("Universal Page Collector", "UPC", owner, controller, 1000);
        console.log(string.concat("CollectorIdentifiableDigitalAsset: deploy ", Strings.toHexString(address(asset))));
    }
}

contract Configure is Script {
    bytes32 private constant _LSP8_TOKEN_METADATA_BASE_URI_KEY =
        0x1a7628600c3bac7101f53697f48df381ddc36b9015e7d7c9c5633d1252aa2843;

    bytes4 private constant _baseUriHash = bytes4(bytes32(keccak256("keccak256(utf8)")));

    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address controller = vm.envAddress("COLLECTOR_CONTROLLER_ADDRESS");
        CollectorIdentifiableDigitalAsset asset =
            CollectorIdentifiableDigitalAsset(payable(vm.envAddress("CONTRACT_COLLECTOR_DIGITAL_ASSET_ADDRESS")));

        bytes memory currentBaseUri = asset.getData(_LSP8_TOKEN_METADATA_BASE_URI_KEY);
        string memory baseUri = vm.envString("COLLECTOR_DIGITAL_ASSET_BASE_URI");
        bytes memory encodedBaseUri = bytes.concat(_baseUriHash, bytes(baseUri));
        if (keccak256(encodedBaseUri) != keccak256(currentBaseUri)) {
            vm.broadcast(owner);
            asset.setData(_LSP8_TOKEN_METADATA_BASE_URI_KEY, encodedBaseUri);
            console.log(string.concat("CollectorIdentifiableDigitalAsset: setBaseUri ", baseUri));
        }

        if (asset.controller() != controller) {
            vm.broadcast(owner);
            asset.setController(controller);
            console.log(
                string.concat("CollectorIdentifiableDigitalAsset: setController ", Strings.toHexString(controller))
            );
        }

        if (asset.beneficiary() != treasury) {
            vm.broadcast(owner);
            asset.setBeneficiary(treasury);
            console.log(
                string.concat("CollectorIdentifiableDigitalAsset: setBeneficiary ", Strings.toHexString(treasury))
            );
        }
    }
}
