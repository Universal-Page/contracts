// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Vault} from "../../src/pool/Vault.sol";
import {DepositContract} from "../../src/pool/IDepositContract.sol";

uint32 constant SERVICE_FEE = 15_000; // 15%
uint256 constant DEPOSIT_LIMIT = 19500 * 32 ether;

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address operator = vm.envAddress("OWNER_ADDRESS");

        address proxy = vm.envOr("CONTRACT_POOL_VAULT", address(0));

        vm.broadcast(admin);
        Vault vault = new Vault();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(vault),
                    admin,
                    abi.encodeWithSelector(Vault.initialize.selector, owner, operator, DepositContract)
                )
            );
            console.log(string.concat("Vault: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(vault));
            console.log(string.concat("Vault: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    function run() external {
        address operator = vm.envAddress("OWNER_ADDRESS");
        address profile = vm.envAddress("PROFILE_ADDRESS");
        address oracle = vm.envAddress("POOL_ORACLE_ADDRESS");

        Vault vault = Vault(payable(vm.envAddress("CONTRACT_POOL_VAULT")));

        if (vault.operator() != operator) {
            console.log(string.concat("Vault: set operator ", Strings.toHexString(operator)));
            vm.broadcast(operator);
            vault.setOperator(operator);
        }

        if (vault.feeRecipient() != profile) {
            console.log(string.concat("Vault: set fee recipient ", Strings.toHexString(profile)));
            vm.broadcast(operator);
            vault.setFeeRecipient(profile);
        }

        if (vault.fee() != SERVICE_FEE) {
            console.log(string.concat("Vault: set fee ", Strings.toString(SERVICE_FEE)));
            vm.broadcast(operator);
            vault.setFee(SERVICE_FEE);
        }

        if (vault.depositLimit() != DEPOSIT_LIMIT) {
            console.log(string.concat("Vault: set deposit limit ", Strings.toString(DEPOSIT_LIMIT)));
            vm.broadcast(operator);
            vault.setDepositLimit(DEPOSIT_LIMIT);
        }

        if (vault.restricted()) {
            console.log("Vault: set not restricted");
            vm.broadcast(operator);
            vault.setRestricted(false);
        }

        if (!vault.isAllowlisted(profile)) {
            console.log(string.concat("Vault: allowlist ", Strings.toHexString(profile)));
            vm.broadcast(operator);
            vault.allowlist(profile, true);
        }

        if (!vault.isOracle(oracle)) {
            console.log(string.concat("Vault: enable oracle ", Strings.toHexString(oracle)));
            vm.broadcast(operator);
            vault.enableOracle(oracle, true);
        }
    }
}
