// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

bytes32 constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");
bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

abstract contract Module is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable {
    error IllegalAccess(address account, bytes32 role);
    error InvalidAddress(address account);

    // role -> account -> granted (yes/no)
    mapping(bytes32 => mapping(address => bool)) private _roles;

    modifier onlyMarketplace() {
        if (!hasRole(msg.sender, MARKETPLACE_ROLE)) {
            revert IllegalAccess(msg.sender, MARKETPLACE_ROLE);
        }
        _;
    }

    modifier onlyOperator() {
        if (!hasRole(msg.sender, OPERATOR_ROLE)) {
            revert IllegalAccess(msg.sender, OPERATOR_ROLE);
        }
        _;
    }

    function _initialize(address newOwner_) internal onlyInitializing {
        __ReentrancyGuard_init();
        __Pausable_init();
        _setOwner(newOwner_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function hasRole(address account, bytes32 role) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(address account, bytes32 role) external onlyOwner {
        _grantRole(account, role);
    }

    function revokeRole(address account, bytes32 role) external onlyOwner {
        _revokeRole(account, role);
    }

    function _grantRole(address account, bytes32 role) internal {
        _roles[role][account] = true;
    }

    function _revokeRole(address account, bytes32 role) internal {
        _roles[role][account] = false;
    }

    // reserved space (20 slots)
    uint256[19] private _module_reserved;
}
