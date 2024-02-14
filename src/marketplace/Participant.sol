// SPDX-License-Identifier: MIT
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {ICollectorIdentifiableDigitalAsset} from "../assets/lsp8/ICollectorIdentifiableDigitalAsset.sol";
import {IParticipant} from "./IParticipant.sol";

uint32 constant GENESIS_DISCOUNT = 20_000;
uint32 constant COLLECTOR_TIER_0_DISCOUNT = 35_000;
uint32 constant COLLECTOR_TIER_1_DISCOUNT = 50_000;
uint32 constant COLLECTOR_TIER_2_DISCOUNT = 75_000;
uint32 constant COLLECTOR_TIER_3_DISCOUNT = 90_000;

contract Participant is IParticipant, OwnableUnset, PausableUpgradeable {
    event AssetFeeDiscountChanged(address indexed asset, uint32 previousDiscountPoints, uint32 newDiscountPoints);
    event CollectorAssetChanged(address indexed previousCollectorAsset, address indexed newCollectorAsset);
    event GenesisAssetChanged(address indexed previousGenesisAsset, address indexed newGenesisAsset);

    ILSP7DigitalAsset public genesisAsset;
    ICollectorIdentifiableDigitalAsset public collectorAsset;

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        __Pausable_init();
        _setOwner(owner_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setCollectorAsset(ICollectorIdentifiableDigitalAsset collectorAsset_) external onlyOwner {
        if (address(collectorAsset) != address(collectorAsset_)) {
            emit CollectorAssetChanged(address(collectorAsset), address(collectorAsset_));
            collectorAsset = collectorAsset_;
        }
    }

    function setGenesisAsset(ILSP7DigitalAsset genesisAsset_) external onlyOwner {
        if (address(genesisAsset) != address(genesisAsset_)) {
            emit GenesisAssetChanged(address(genesisAsset), address(genesisAsset_));
            genesisAsset = genesisAsset_;
        }
    }

    function feeDiscountFor(address profile) external view override whenNotPaused returns (uint32) {
        uint32 maxDiscount = 0;
        if (
            (address(genesisAsset) != address(0)) && (genesisAsset.balanceOf(profile) != 0)
                && (maxDiscount < GENESIS_DISCOUNT)
        ) {
            maxDiscount = GENESIS_DISCOUNT;
        }
        if (address(collectorAsset) != address(0)) {
            bytes32[] memory tokenIds = collectorAsset.tokenIdsOf(profile);
            for (uint256 i = 0; i < tokenIds.length; i++) {
                uint8 tier = collectorAsset.tokenTierOf(tokenIds[i]);
                uint32 discount = 0;
                if (tier == 0) {
                    discount = COLLECTOR_TIER_0_DISCOUNT;
                } else if (tier == 1) {
                    discount = COLLECTOR_TIER_1_DISCOUNT;
                } else if (tier == 2) {
                    discount = COLLECTOR_TIER_2_DISCOUNT;
                } else if (tier == 3) {
                    discount = COLLECTOR_TIER_3_DISCOUNT;
                }
                if (maxDiscount < discount) {
                    maxDiscount = discount;
                }
            }
        }
        return maxDiscount;
    }
}
