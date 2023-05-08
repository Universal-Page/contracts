// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {
    LSP8IdentifiableDigitalAsset,
    LSP8IdentifiableDigitalAssetCore
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {_INTERFACEID_LSP8} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {LSP8CappedSupply} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8CappedSupply.sol";
import {LSP8Enumerable} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8Enumerable.sol";
import {_LSP8_TOKENID_FORMAT_NUMBER} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {DropsLightAsset} from "./DropsLightAsset.sol";

contract LSP8DropsLightAsset is LSP8CappedSupply, LSP8Enumerable, DropsLightAsset {
    event Minted(address indexed recipient, bytes32[] tokenIds, uint256 totalPrice);
    event DefaultTokenDataChanged(bytes defaultTokenData);

    bytes32 private constant _LSP8_TOKEN_METADATA_BASE_URI_KEY =
        0x1a7628600c3bac7101f53697f48df381ddc36b9015e7d7c9c5633d1252aa2843;

    bytes32 private constant _LSP4_METADATA_KEY = 0x9afb95cacc9f95858ec44aa8c3b685511002e30ae54415823f406128b85b238e;

    bytes public defaultTokenUri;
    uint256 private _totalMintedTokens;

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
        LSP8IdentifiableDigitalAsset(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_NUMBER)
        LSP8CappedSupply(tokenSupplyCap_)
        DropsLightAsset(beneficiary_, service_, verifier_, serviceFeePoints_)
    {}

    function setDefaultTokenUri(bytes calldata newTokenUri) external onlyOwner {
        defaultTokenUri = newTokenUri;
        emit DefaultTokenDataChanged(newTokenUri);
    }

    function _getDataForTokenId(bytes32 tokenId, bytes32 dataKey) internal view override returns (bytes memory) {
        bytes memory result = super._getDataForTokenId(tokenId, dataKey);
        if (dataKey == _LSP4_METADATA_KEY && result.length == 0) {
            bytes memory baseUri = super._getData(_LSP8_TOKEN_METADATA_BASE_URI_KEY);
            if (baseUri.length == 0) {
                return defaultTokenUri;
            }
        }
        return result;
    }

    function _doMint(address recipient, uint256 amount, uint256 totalPrice) internal override {
        // allocate tokens
        bytes32[] memory tokenIds = new bytes32[](amount);
        uint256 firstTokenId = _totalMintedTokens + 1;
        _totalMintedTokens += amount;
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = bytes32(firstTokenId + i);
        }
        emit Minted(recipient, tokenIds, totalPrice);
        // mint tokens
        for (uint256 i = 0; i < amount; i++) {
            _mint(recipient, tokenIds[i], true, "");
        }
    }

    function balanceOf(address tokenOwner)
        public
        view
        virtual
        override(LSP8IdentifiableDigitalAssetCore, DropsLightAsset)
        returns (uint256)
    {
        return super.balanceOf(tokenOwner);
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
