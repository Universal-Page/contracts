// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {OPERATION_0_CALL} from "@erc725/smart-contracts/contracts/constants.sol";
import {Elections} from "../src/Elections.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address profile = vm.envAddress("PROFILE_ADDRESS");

        address proxy = vm.envOr("CONTRACT_ELECTIONS", address(0));

        vm.broadcast(admin);
        Elections elections = new Elections();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(elections),
                    admin,
                    abi.encodeWithSelector(Elections.initialize.selector, profile)
                )
            );
            console.log(string.concat("Elections: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(elections));
            console.log(string.concat("Elections: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    function run() external {
        // address controller = vm.envAddress("PROFILE_CONTROLLER_ADDRESS");
        // address treasury = vm.envAddress("TREASURY_ADDRESS");
        // UniversalProfile profile = UniversalProfile(payable(vm.envAddress("PROFILE_ADDRESS")));
        // Elections elections = Elections(payable(vm.envAddress("CONTRACT_ELECTIONS")));

        // if (elections.beneficiary() != treasury) {
        //     vm.broadcast(controller);
        //     profile.execute(
        //         OPERATION_0_CALL,
        //         address(elections),
        //         0,
        //         abi.encodeWithSelector(elections.setBeneficiary.selector, treasury)
        //     );
        // }
    }
}
