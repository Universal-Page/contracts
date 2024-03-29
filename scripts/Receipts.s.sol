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
import {Receipts} from "../src/Receipts.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address profile = vm.envAddress("PROFILE_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        address proxy = vm.envOr("CONTRACT_RECEIPTS", address(0));

        vm.broadcast(admin);
        Receipts receipts = new Receipts();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(receipts),
                    admin,
                    abi.encodeWithSelector(Receipts.initialize.selector, profile, treasury)
                )
            );
            console.log(string.concat("Receipts: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(receipts));
            console.log(string.concat("Receipts: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    function run() external {
        address controller = vm.envAddress("PROFILE_CONTROLLER_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        UniversalProfile profile = UniversalProfile(payable(vm.envAddress("PROFILE_ADDRESS")));
        Receipts receipts = Receipts(payable(vm.envAddress("CONTRACT_RECEIPTS")));

        if (receipts.beneficiary() != treasury) {
            vm.broadcast(controller);
            profile.execute(
                OPERATION_0_CALL,
                address(receipts),
                0,
                abi.encodeWithSelector(receipts.setBeneficiary.selector, treasury)
            );
        }
    }
}
