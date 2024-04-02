// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProfilesOracle} from "../../src/profiles/ProfilesOracle.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address operator = vm.envAddress("OWNER_ADDRESS");

        address proxy = vm.envOr("CONTRACT_PROFILES_ORACLE", address(0));

        vm.broadcast(admin);
        ProfilesOracle oracle = new ProfilesOracle();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(oracle),
                    admin,
                    abi.encodeWithSelector(ProfilesOracle.initialize.selector, owner, operator)
                )
            );
            console.log(string.concat("ProfilesOracle: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(oracle));
            console.log(string.concat("ProfilesOracle: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}
