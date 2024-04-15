// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {
    LSP8IdentifiableDigitalAsset,
    LSP8IdentifiableDigitalAssetCore
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {LSP8Enumerable} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8Enumerable.sol";
import {LSP8CappedSupply} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8CappedSupply.sol";
import {
    _LSP8_TOKEN_METADATA_BASE_URI,
    _LSP8_TOKENID_FORMAT_NUMBER
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {LSP8CompatibleERC721} from "../common/LSP8CompatibleERC721.sol";
import {LSP8CompatibleERC721Enumerable} from "../common/LSP8CompatibleERC721Enumerable.sol";
import {DropsLightAsset} from "./DropsLightAsset.sol";

contract LSP8DropsLightAsset is
    LSP8CompatibleERC721,
    LSP8CompatibleERC721Enumerable,
    LSP8CappedSupply,
    DropsLightAsset
{
    event Minted(address indexed recipient, bytes32[] tokenIds, uint256 totalPrice);
    event DefaultTokenDataChanged(bytes defaultTokenData);

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
        LSP8CompatibleERC721(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_NUMBER)
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
            bytes memory baseUri = super._getData(_LSP8_TOKEN_METADATA_BASE_URI);
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

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(LSP8CompatibleERC721Enumerable, LSP8CompatibleERC721, LSP8IdentifiableDigitalAsset)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function totalSupply()
        public
        view
        virtual
        override(LSP8CompatibleERC721Enumerable, LSP8IdentifiableDigitalAssetCore)
        returns (uint256)
    {
        return super.totalSupply();
    }

    function balanceOf(address tokenOwner)
        public
        view
        virtual
        override(LSP8CompatibleERC721Enumerable, LSP8CompatibleERC721, LSP8IdentifiableDigitalAssetCore, DropsLightAsset)
        returns (uint256)
    {
        return super.balanceOf(tokenOwner);
    }

    function _mint(address to, bytes32 tokenId, bool allowNonLSP1Recipient, bytes memory data)
        internal
        virtual
        override(LSP8CappedSupply, LSP8CompatibleERC721, LSP8IdentifiableDigitalAssetCore)
    {
        super._mint(to, tokenId, allowNonLSP1Recipient, data);
    }

    function _beforeTokenTransfer(address from, address to, bytes32 tokenId, bytes memory data)
        internal
        virtual
        override(LSP8Enumerable, LSP8IdentifiableDigitalAssetCore)
    {
        super._beforeTokenTransfer(from, to, tokenId, data);
    }

    function authorizeOperator(address operator, bytes32 tokenId, bytes memory operatorNotificationData)
        public
        virtual
        override(LSP8CompatibleERC721, LSP8IdentifiableDigitalAssetCore)
    {
        super.authorizeOperator(operator, tokenId, operatorNotificationData);
    }

    function _transfer(address from, address to, bytes32 tokenId, bool force, bytes memory data)
        internal
        virtual
        override(LSP8CompatibleERC721, LSP8IdentifiableDigitalAssetCore)
    {
        super._transfer(from, to, tokenId, force, data);
    }

    function _burn(bytes32 tokenId, bytes memory data)
        internal
        virtual
        override(LSP8CompatibleERC721, LSP8IdentifiableDigitalAssetCore)
    {
        super._burn(tokenId, data);
    }
}
