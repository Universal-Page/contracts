// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IParticipant} from "../../../src/marketplace/IParticipant.sol";
import {LSP8Marketplace} from "../../../src/marketplace/lsp8/LSP8Marketplace.sol";
import {Module, MARKETPLACE_ROLE} from "../../../src/marketplace/common/Module.sol";

uint32 constant FEE_POINTS = 2_500;
uint32 constant ROYALTIES_THRESHOLD_POINTS = 10_000;

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address listings = vm.envAddress("CONTRACT_LSP7_LISTINGS_ADDRESS");
        address offers = vm.envAddress("CONTRACT_LSP7_OFFERS_ADDRESS");
        address auctions = vm.envAddress("CONTRACT_LSP8_AUCTIONS_ADDRESS");
        address participant = vm.envAddress("CONTRACT_PARTICIPANT_ADDRESS");

        address proxy = vm.envOr("CONTRACT_LSP8_MARKETPLACE_ADDRESS", address(0));

        vm.broadcast(admin);
        LSP8Marketplace marketplace = new LSP8Marketplace();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(marketplace),
                    admin,
                    abi.encodeWithSelector(LSP8Marketplace.initialize.selector, owner, treasury, listings, offers, auctions, participant)
                )
            );
            console.log(string.concat("LSP8Marketplace: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(marketplace));
            console.log(string.concat("LSP8Marketplace: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Claim is Script {
    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        LSP8Marketplace marketplace = LSP8Marketplace(payable(vm.envAddress("CONTRACT_LSP8_MARKETPLACE_ADDRESS")));

        if (address(marketplace).balance > 0) {
            vm.broadcast(owner);
            marketplace.withdraw(address(marketplace).balance);
        }
    }
}

contract Configure is Script {
    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        IParticipant participant = IParticipant(vm.envAddress("CONTRACT_PARTICIPANT_ADDRESS"));
        Module listings = Module(vm.envAddress("CONTRACT_LSP8_LISTINGS_ADDRESS"));
        Module offers = Module(vm.envAddress("CONTRACT_LSP8_OFFERS_ADDRESS"));
        Module auctions = Module(vm.envAddress("CONTRACT_LSP8_AUCTIONS_ADDRESS"));

        LSP8Marketplace marketplace = LSP8Marketplace(payable(vm.envAddress("CONTRACT_LSP8_MARKETPLACE_ADDRESS")));

        if (marketplace.feePoints() != FEE_POINTS) {
            vm.broadcast(owner);
            marketplace.setFeePoints(FEE_POINTS);
        }

        if (marketplace.royaltiesThresholdPoints() != ROYALTIES_THRESHOLD_POINTS) {
            vm.broadcast(owner);
            marketplace.setRoyaltiesThresholdPoints(ROYALTIES_THRESHOLD_POINTS);
        }

        if (!listings.hasRole(address(marketplace), MARKETPLACE_ROLE)) {
            vm.broadcast(owner);
            listings.grantRole(address(marketplace), MARKETPLACE_ROLE);
        }

        if (!listings.hasRole(address(auctions), MARKETPLACE_ROLE)) {
            vm.broadcast(owner);
            listings.grantRole(address(auctions), MARKETPLACE_ROLE);
        }

        if (!offers.hasRole(address(marketplace), MARKETPLACE_ROLE)) {
            vm.broadcast(owner);
            offers.grantRole(address(marketplace), MARKETPLACE_ROLE);
        }

        if (!auctions.hasRole(address(marketplace), MARKETPLACE_ROLE)) {
            vm.broadcast(owner);
            auctions.grantRole(address(marketplace), MARKETPLACE_ROLE);
        }

        if (marketplace.beneficiary() != treasury) {
            vm.broadcast(owner);
            marketplace.setBeneficiary(treasury);
        }

        if (address(marketplace.participant()) != address(participant)) {
            vm.broadcast(owner);
            marketplace.setParticipant(participant);
        }
    }
}
