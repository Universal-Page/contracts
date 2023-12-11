// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {
    LSP7DigitalAsset,
    LSP7DigitalAssetCore
} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAsset.sol";
import {LSP7CappedSupply} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/extensions/LSP7CappedSupply.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {DropsDigitalAsset} from "./DropsDigitalAsset.sol";

contract LSP7DropsDigitalAsset is LSP7CappedSupply, DropsDigitalAsset {
    event Minted(address indexed recipient, uint256 amount, uint256 totalPrice);

    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        address service_,
        address verifier_,
        uint256 tokenSupplyCap_,
        uint32 serviceFeePoints_
    )
        LSP7DigitalAsset(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, true)
        LSP7CappedSupply(tokenSupplyCap_)
        DropsDigitalAsset(service_, verifier_, serviceFeePoints_)
    {}

    function _doMint(address recipient, uint256 amount, uint256 totalPrice) internal override {
        emit Minted(recipient, amount, totalPrice);
        _mint(recipient, amount, false, "");
    }

    function balanceOf(address tokenOwner)
        public
        view
        virtual
        override(LSP7DigitalAssetCore, DropsDigitalAsset)
        returns (uint256)
    {
        return super.balanceOf(tokenOwner);
    }
}
