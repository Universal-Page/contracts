// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Merkle} from "murky/Merkle.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {OPERATION_0_CALL} from "@erc725/smart-contracts/contracts/constants.sol";
import {GenesisDigitalAsset} from "../../../src/assets/lsp7/GenesisDigitalAsset.sol";
import {DigitalAssetDrop} from "../../../src/assets/lsp7/DigitalAssetDrop.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address profile = vm.envAddress("PROFILE_ADDRESS");

        vm.broadcast(admin);
        GenesisDigitalAsset asset = new GenesisDigitalAsset("Universal Page Genesis", "UPG", profile, profile);
        console.log(string.concat("GenesisDigitalAsset: ", Strings.toHexString(address(asset))));
    }
}

contract Drop is Script {
    struct Claim {
        uint256 amount;
        address profile;
    }

    struct Data {
        Claim[] claims;
    }

    function run() external {
        address controller = vm.envAddress("PROFILE_CONTROLLER_ADDRESS");
        UniversalProfile profile = UniversalProfile(payable(vm.envAddress("PROFILE_ADDRESS")));
        GenesisDigitalAsset genesisAsset =
            GenesisDigitalAsset(payable(vm.envAddress("CONTRACT_GENESIS_DIGITAL_ASSET_ADDRESS")));

        uint256 fundAmount = 0;

        // build merkle tree
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(), "/scripts/assets/lsp7/data/", Strings.toString(block.chainid), "/genesis.json"
            )
        );
        Data memory jsonData = abi.decode(vm.parseJson(json), (Data));

        console.log("Allowlist claims:", jsonData.claims.length);
        bytes32[] memory data = new bytes32[](jsonData.claims.length);
        for (uint256 i = 0; i < jsonData.claims.length; i++) {
            Claim memory claim = jsonData.claims[i];
            console.log("-", i, claim.profile, claim.amount);
            data[i] = keccak256(abi.encodePacked(i, claim.profile, claim.amount));
            console.logBytes32(data[i]);
            fundAmount += claim.amount;
        }

        Merkle merkle = new Merkle();
        bytes32 root = merkle.getRoot(data);

        // deploy drop
        vm.broadcast(controller);
        DigitalAssetDrop drop = new DigitalAssetDrop(genesisAsset, root, address(profile));
        console.log(string.concat("DigitalAssetDrop: ", Strings.toHexString(address(drop))));

        // fund drop
        console.log("Fund drop:", fundAmount);
        vm.startBroadcast(controller);
        profile.execute(
            OPERATION_0_CALL,
            address(genesisAsset),
            0,
            abi.encodeWithSelector(genesisAsset.reserve.selector, fundAmount)
        );
        profile.execute(
            OPERATION_0_CALL,
            address(genesisAsset),
            0,
            abi.encodeWithSelector(
                genesisAsset.transfer.selector, address(profile), address(drop), fundAmount, true, ""
            )
        );
        vm.stopBroadcast();

        // generate proofs
        {
            string memory claimsJson = "{}";
            for (uint256 i = 0; i < jsonData.claims.length; i++) {
                Claim memory claim = jsonData.claims[i];
                bytes32[] memory proof = merkle.getProof(data, i);

                string memory object = string.concat("claim-", Strings.toString(i));
                vm.serializeUint(object, "index", i);
                vm.serializeAddress(object, "profile", claim.profile);
                vm.serializeUint(object, "amount", claim.amount);
                string memory json = vm.serializeBytes32(object, "proof", proof);

                claimsJson = vm.serializeString("claims", Strings.toString(i), json);
            }

            vm.serializeString("", "claims", claimsJson);
            string memory json = vm.serializeAddress("", "address", address(drop));

            string memory outputDir =
                string.concat(vm.projectRoot(), "/artifacts/data/", Strings.toString(block.chainid));
            vm.createDir(outputDir, true);
            vm.writeJson(json, string.concat(outputDir, "/genesis.json"));
        }
    }
}
