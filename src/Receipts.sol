// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Withdrawable} from "./common/Withdrawable.sol";

contract Receipts is ReentrancyGuardUpgradeable, PausableUpgradeable, Withdrawable {
    error ZeroPayment();

    event Paid(address indexed payer, uint256 amount, bytes data);

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_, address beneficiary_) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        _setOwner(newOwner_);
        _setBeneficiary(beneficiary_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function pay(bytes calldata data) external payable whenNotPaused nonReentrant {
        if (msg.value == 0) {
            revert ZeroPayment();
        }
        emit Paid(msg.sender, msg.value, data);
    }
}
