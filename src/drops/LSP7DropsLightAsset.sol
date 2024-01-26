// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {
    LSP7DigitalAsset,
    LSP7DigitalAssetCore
} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/LSP7DigitalAsset.sol";
import {LSP7CappedSupply} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/extensions/LSP7CappedSupply.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {DropsLightAsset} from "./DropsLightAsset.sol";

contract LSP7DropsLightAsset is LSP7CappedSupply, DropsLightAsset {
    event Minted(address indexed recipient, uint256 amount, uint256 totalPrice);

    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        address beneficiary_,
        address service_,
        address verifier_,
        uint256 tokenSupplyCap_,
        uint32 serviceFeePoints_
    )
        LSP7DigitalAsset(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, true)
        LSP7CappedSupply(tokenSupplyCap_)
        DropsLightAsset(beneficiary_, service_, verifier_, serviceFeePoints_)
    {}

    function _doMint(address recipient, uint256 amount, uint256 totalPrice) internal override {
        emit Minted(recipient, amount, totalPrice);
        _mint(recipient, amount, true, "");
    }

    function balanceOf(address tokenOwner)
        public
        view
        virtual
        override(LSP7DigitalAssetCore, DropsLightAsset)
        returns (uint256)
    {
        return super.balanceOf(tokenOwner);
    }
}
