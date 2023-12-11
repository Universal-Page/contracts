// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {LSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAsset.sol";

contract LSP7DigitalAssetMock is LSP7DigitalAsset {
    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        uint256 lsp4TokenType_,
        bool isNonDivisible_
    ) LSP7DigitalAsset(name_, symbol_, newOwner_, lsp4TokenType_, isNonDivisible_) {}

    function mint(address to, uint256 amount, bool allowNonLSP1Recipient, bytes memory data) external {
        _mint(to, amount, allowNonLSP1Recipient, data);
    }
}
