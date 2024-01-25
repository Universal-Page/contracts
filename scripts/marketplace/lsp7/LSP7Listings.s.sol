// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LSP7Listings} from "../../../src/marketplace/lsp7/LSP7Listings.sol";
import {OPERATOR_ROLE} from "../../../src/marketplace/common/Module.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        address proxy = vm.envOr("CONTRACT_LSP7_LISTINGS_ADDRESS", address(0));

        vm.broadcast(admin);
        LSP7Listings listings = new LSP7Listings();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(listings), admin, abi.encodeWithSelector(LSP7Listings.initialize.selector, owner)
                )
            );
            console.log(string.concat("LSP7Listings: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(listings));
            console.log(string.concat("LSP7Listings: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address operator = vm.envAddress("MARKETPLACE_OPERATOR_ADDRESS");
        LSP7Listings listings = LSP7Listings(vm.envAddress("CONTRACT_LSP7_LISTINGS_ADDRESS"));

        if (!listings.hasRole(operator, OPERATOR_ROLE)) {
            vm.broadcast(owner);
            listings.grantRole(operator, OPERATOR_ROLE);
        }
    }
}
