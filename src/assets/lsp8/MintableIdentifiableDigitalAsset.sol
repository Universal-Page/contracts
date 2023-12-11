// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {LSP8IdentifiableDigitalAssetCore} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAssetCore.sol";
import {LSP8Mintable} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/presets/LSP8Mintable.sol";
import {LSP8Enumerable} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8Enumerable.sol";
import {LSP8CappedSupply} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8CappedSupply.sol";

contract MintableIdentifiableDigitalAsset is LSP8Mintable, LSP8Enumerable, LSP8CappedSupply {
    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        uint256 tokenIdType_,
        uint256 lsp8TokenIdSchema_,
        uint256 tokenSupplyCap_
    ) LSP8Mintable(name_, symbol_, newOwner_, tokenIdType_, lsp8TokenIdSchema_) LSP8CappedSupply(tokenSupplyCap_) {
        // noop
    }

    function _mint(address to, bytes32 tokenId, bool allowNonLSP1Recipient, bytes memory data)
        internal
        virtual
        override(LSP8IdentifiableDigitalAssetCore, LSP8CappedSupply)
    {
        super._mint(to, tokenId, allowNonLSP1Recipient, data);
    }

    function _beforeTokenTransfer(address from, address to, bytes32 tokenId, bytes memory data)
        internal
        virtual
        override(LSP8IdentifiableDigitalAssetCore, LSP8Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, data);
    }
}
