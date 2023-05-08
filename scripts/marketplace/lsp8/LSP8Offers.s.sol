// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LSP8Offers} from "../../../src/marketplace/lsp8/LSP8Offers.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address listings = vm.envAddress("CONTRACT_LSP8_LISTINGS_ADDRESS");

        address proxy = vm.envOr("CONTRACT_LSP8_OFFERS_ADDRESS", address(0));

        vm.broadcast(admin);
        LSP8Offers offers = new LSP8Offers();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(offers),
                    admin,
                    abi.encodeWithSelector(LSP8Offers.initialize.selector, owner, listings)
                )
            );
            console.log(string.concat("LSP8Offers: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(offers));
            console.log(string.concat("LSP8Offers: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}
