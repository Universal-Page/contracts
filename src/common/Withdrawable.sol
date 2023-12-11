// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";

abstract contract Withdrawable is OwnableUnset {
    error InvalidBeneficiary(address account);
    error DispositionFailure(address beneficiary, uint256 amount);

    event ValueReceived(address indexed sender, uint256 indexed value);
    event ValueWithdrawn(address indexed beneficiary, uint256 indexed value);
    event BeneficiaryChanged(address indexed oldBeneficiary, address indexed newBeneficiary);

    address public beneficiary;

    receive() external payable virtual {
        _doReceive();
    }

    function _doReceive() internal virtual {
        if (msg.value > 0) {
            emit ValueReceived(msg.sender, msg.value);
        }
    }

    function setBeneficiary(address newBeneficiary) external onlyOwner {
        _setBeneficiary(newBeneficiary);
    }

    function _setBeneficiary(address newBeneficiary) internal virtual {
        if (newBeneficiary == address(0)) {
            revert InvalidBeneficiary(newBeneficiary);
        }
        if (beneficiary != newBeneficiary) {
            address oldBeneficiary = beneficiary;
            beneficiary = newBeneficiary;
            emit BeneficiaryChanged(oldBeneficiary, newBeneficiary);
        }
    }

    function withdraw(uint256 amount) external onlyOwner {
        if (beneficiary == address(0)) {
            revert InvalidBeneficiary(beneficiary);
        }
        (bool success,) = beneficiary.call{value: amount}("");
        if (!success) {
            revert DispositionFailure(beneficiary, amount);
        }
        emit ValueWithdrawn(beneficiary, amount);
    }

    // reserved space (10 slots)
    uint256[9] private _reserved;
}
