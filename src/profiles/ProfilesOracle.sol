// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ERC725YInitAbstract} from "@erc725/smart-contracts/contracts/ERC725YInitAbstract.sol";
import {ERC725YCore} from "@erc725/smart-contracts/contracts/ERC725YCore.sol";
import {
    ERC725Y_DataKeysValuesLengthMismatch,
    ERC725Y_DataKeysValuesEmptyArray
} from "@erc725/smart-contracts/contracts/errors.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

contract ProfilesOracle is ERC725YInitAbstract, AccessControlUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address operator) external initializer {
        ERC725YInitAbstract._initialize(initialOwner);
        _setRoleAdmin(ORACLE_ROLE, OPERATOR_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, OPERATOR_ROLE);
        _grantRole(OPERATOR_ROLE, operator);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC725YCore, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function submitData(bytes32[] calldata dataKeys, bytes[] calldata dataValues) external onlyRole(ORACLE_ROLE) {
        if (dataKeys.length != dataValues.length) {
            revert ERC725Y_DataKeysValuesLengthMismatch();
        }
        if (dataKeys.length == 0) {
            revert ERC725Y_DataKeysValuesEmptyArray();
        }
        for (uint256 i = 0; i < dataKeys.length; i++) {
            _setData(dataKeys[i], dataValues[i]);
        }
    }
}
