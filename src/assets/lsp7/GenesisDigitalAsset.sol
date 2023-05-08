// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {LSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAsset.sol";

contract GenesisDigitalAsset is LSP7DigitalAsset {
    error InvalidBeneficiary();
    error UnathorizedAccount(address account);

    event BeneficiaryChanged(address indexed oldBeneficiary, address indexed newBeneficiary);

    address public beneficiary;

    constructor(string memory name_, string memory symbol_, address newOwner_, address newBeneficiary_)
        LSP7DigitalAsset(name_, symbol_, newOwner_, true)
    {
        _setBeneficiary(newBeneficiary_);
    }

    function setBeneficiary(address newBeneficiary) external onlyOwner {
        _setBeneficiary(newBeneficiary);
    }

    function _setBeneficiary(address newBeneficiary) internal virtual {
        if (newBeneficiary == address(0)) {
            revert InvalidBeneficiary();
        }
        if (beneficiary != newBeneficiary) {
            address oldBeneficiary = beneficiary;
            beneficiary = newBeneficiary;
            emit BeneficiaryChanged(oldBeneficiary, newBeneficiary);
        }
    }

    function reserve(uint256 amount) external onlyOwner {
        _mint(beneficiary, amount, true, "");
    }

    function release(uint256 amount) external {
        _burn(beneficiary, amount, "");
    }
}
