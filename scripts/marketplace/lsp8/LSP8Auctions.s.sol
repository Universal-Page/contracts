// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LSP8Auctions} from "../../../src/marketplace/lsp8/LSP8Auctions.sol";

uint32 constant BID_MIN_DELTA_POINTS = 2_000;
uint256 constant BID_TIME_EXTENSION = 5 minutes;

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address listings = vm.envAddress("CONTRACT_LSP8_LISTINGS_ADDRESS");

        address proxy = vm.envOr("CONTRACT_LSP8_AUCTIONS_ADDRESS", address(0));

        vm.broadcast(admin);
        LSP8Auctions auctions = new LSP8Auctions();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(auctions),
                    admin,
                    abi.encodeWithSelector(LSP8Auctions.initialize.selector, owner, listings)
                )
            );
            console.log(string.concat("LSP8Auctions: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(auctions));
            console.log(string.concat("LSP8Auctions: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        LSP8Auctions auctions = LSP8Auctions(payable(vm.envAddress("CONTRACT_LSP8_AUCTIONS_ADDRESS")));

        if (auctions.bidTimeExtension() != BID_TIME_EXTENSION) {
            console.log("Setting bid time extension");
            vm.broadcast(owner);
            auctions.setBidTimeExtension(BID_TIME_EXTENSION);
        }

        if (auctions.minBidDetlaPoints() != BID_MIN_DELTA_POINTS) {
            console.log("Setting min bid delta points");
            vm.broadcast(owner);
            auctions.setMinBidDetlaPoints(BID_MIN_DELTA_POINTS);
        }
    }
}
