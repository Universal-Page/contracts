// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {BytesLib} from "solidity-bytes-utils/contracts/BytesLib.sol";

bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

uint8 constant TOKEN_PROFILE = 0x01;
uint8 constant TOKEN_PROFILE_SCORE = 0x02;

contract Profiles is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable {
    error RoleNotGranted(address account, bytes32 role);
    error RoleUnchanged(address account, bytes32 role);
    error InvalidToken(uint8 token);

    event RoleGranted(address indexed account, bytes32 role);
    event RoleRevoked(address indexed account, bytes32 role);
    event ProfileScoreChanged(address indexed profile, uint32 score);

    mapping(bytes32 role => mapping(address account => bool granted)) private _roles;
    mapping(address profile => uint32 score) private _profilesScores;
    mapping(address profile => uint256 updatedBlock) private _profilesUpdatedBlocks;

    modifier onlyRole(bytes32 role) {
        if (!hasRole(msg.sender, role)) {
            revert RoleNotGranted(msg.sender, role);
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_) external initializer {
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
        if (hasRole(account, role)) {
            revert RoleUnchanged(account, role);
        }
        _roles[role][account] = true;
        emit RoleGranted(account, role);
    }

    function _revokeRole(address account, bytes32 role) internal {
        if (!hasRole(account, role)) {
            revert RoleUnchanged(account, role);
        }
        _roles[role][account] = false;
        emit RoleRevoked(account, role);
    }

    function scoreOf(address profile) external view whenNotPaused returns (uint32) {
        return _profilesScores[profile];
    }

    function updatedBlockOf(address profile) external view whenNotPaused returns (uint256) {
        return _profilesUpdatedBlocks[profile];
    }

    function submit(bytes calldata data) external whenNotPaused onlyRole(ORACLE_ROLE) {
        for (uint256 offset = 0; offset < data.length;) {
            uint8 token = BytesLib.toUint8(data, offset);
            offset += 1;

            if (token == TOKEN_PROFILE) {
                address profile = BytesLib.toAddress(data, offset);
                offset += 20;

                _profilesUpdatedBlocks[profile] = block.number;

                while (offset < data.length) {
                    token = BytesLib.toUint8(data, offset);
                    if (token == TOKEN_PROFILE) {
                        break;
                    }
                    offset += 1;

                    if (token == TOKEN_PROFILE_SCORE) {
                        uint32 score = BytesLib.toUint32(data, offset);
                        offset += 4;

                        _profilesScores[profile] = score;
                        emit ProfileScoreChanged(profile, score);
                    } else {
                        revert InvalidToken(token);
                    }
                }
            } else {
                revert InvalidToken(token);
            }
        }
    }
}
