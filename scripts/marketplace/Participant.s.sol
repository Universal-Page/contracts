// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {ICollectorIdentifiableDigitalAsset} from "../../src/assets/lsp8/ICollectorIdentifiableDigitalAsset.sol";
import {Participant} from "../../src/marketplace/Participant.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        address proxy = vm.envOr("CONTRACT_PARTICIPANT_ADDRESS", address(0));

        vm.broadcast(admin);
        Participant participant = new Participant();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(participant),
                    admin,
                    abi.encodeWithSelector(Participant.initialize.selector, owner)
                )
            );
            console.log(string.concat("Participant: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(participant));
            console.log(string.concat("Participant: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        ICollectorIdentifiableDigitalAsset collectorAsset =
            ICollectorIdentifiableDigitalAsset(vm.envOr("CONTRACT_COLLECTOR_DIGITAL_ASSET_ADDRESS", address(0)));
        ILSP7DigitalAsset genesisAsset =
            ILSP7DigitalAsset(vm.envOr("CONTRACT_GENESIS_DIGITAL_ASSET_ADDRESS", address(0)));
        Participant participant = Participant(vm.envAddress("CONTRACT_PARTICIPANT_ADDRESS"));

        if (address(participant.collectorAsset()) != address(collectorAsset)) {
            vm.broadcast(owner);
            participant.setCollectorAsset(collectorAsset);
            console.log(string.concat("Participant: setCollectorAsset ", Strings.toHexString(address(collectorAsset))));
        }

        if (address(participant.genesisAsset()) != address(genesisAsset)) {
            vm.broadcast(owner);
            participant.setGenesisAsset(genesisAsset);
            console.log(string.concat("Participant: setGenesisAsset ", Strings.toHexString(address(genesisAsset))));
        }
    }
}
