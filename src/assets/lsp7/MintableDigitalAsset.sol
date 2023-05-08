// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {LSP7Mintable} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/presets/LSP7Mintable.sol";
import {LSP7DigitalAssetCore} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAssetCore.sol";
import {LSP7CappedSupply} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/extensions/LSP7CappedSupply.sol";

contract MintableDigitalAsset is LSP7Mintable, LSP7CappedSupply {
    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        uint256 lsp4TokenType_,
        bool isNonDivisible_,
        uint256 tokenSupplyCap_
    ) LSP7Mintable(name_, symbol_, newOwner_, lsp4TokenType_, isNonDivisible_) LSP7CappedSupply(tokenSupplyCap_) {}

    function _mint(address to, uint256 amount, bool allowNonLSP1Recipient, bytes memory data)
        internal
        virtual
        override(LSP7DigitalAssetCore, LSP7CappedSupply)
    {
        super._mint(to, amount, allowNonLSP1Recipient, data);
    }
}
