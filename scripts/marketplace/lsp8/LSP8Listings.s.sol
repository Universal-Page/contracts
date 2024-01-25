// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LSP8Listings} from "../../../src/marketplace/lsp8/LSP8Listings.sol";
import {OPERATOR_ROLE} from "../../../src/marketplace/common/Module.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        address proxy = vm.envOr("CONTRACT_LSP8_LISTINGS_ADDRESS", address(0));

        vm.broadcast(admin);
        LSP8Listings listings = new LSP8Listings();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(listings), admin, abi.encodeWithSelector(LSP8Listings.initialize.selector, owner)
                )
            );
            console.log(string.concat("LSP8Listings: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(listings));
            console.log(string.concat("LSP8Listings: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address operator = vm.envAddress("MARKETPLACE_OPERATOR_ADDRESS");
        LSP8Listings listings = LSP8Listings(vm.envAddress("CONTRACT_LSP8_LISTINGS_ADDRESS"));

        if (!listings.hasRole(operator, OPERATOR_ROLE)) {
            vm.broadcast(owner);
            listings.grantRole(operator, OPERATOR_ROLE);
        }
    }
}
