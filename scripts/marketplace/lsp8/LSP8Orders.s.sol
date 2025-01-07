// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LSP8Orders} from "../../../src/marketplace/lsp8/LSP8Orders.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        address proxy = vm.envOr("CONTRACT_LSP8_ORDERS_ADDRESS", address(0));

        vm.broadcast(admin);
        LSP8Orders orders = new LSP8Orders();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(orders), admin, abi.encodeWithSelector(LSP8Orders.initialize.selector, owner)
                )
            );
            console.log(string.concat("LSP8Orders: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(orders));
            console.log(string.concat("LSP8Orders: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}
