// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {LSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAsset.sol";
import {LSP7DigitalAssetCore} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAssetCore.sol";
import {LSP7CappedSupply} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/extensions/LSP7CappedSupply.sol";
import {_LSP4_TOKEN_TYPE_TOKEN} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";

contract PageToken is LSP7DigitalAsset, LSP7CappedSupply {
    constructor(address newOwner_)
        LSP7DigitalAsset("Page", "PAGE", newOwner_, _LSP4_TOKEN_TYPE_TOKEN, false)
        LSP7CappedSupply(10_000_000)
    {}

    function _mint(address to, uint256 amount, bool force, bytes memory data)
        internal
        virtual
        override(LSP7CappedSupply, LSP7DigitalAssetCore)
    {
        super._mint(to, amount, force, data);
    }
}
