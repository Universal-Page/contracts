// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {
    LSP8IdentifiableDigitalAsset,
    LSP8IdentifiableDigitalAssetCore
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {LSP8CappedSupply} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8CappedSupply.sol";
import {LSP8Enumerable} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8Enumerable.sol";
import {DropsDigitalAsset} from "./DropsDigitalAsset.sol";

contract LSP8DropsDigitalAsset is LSP8CappedSupply, LSP8Enumerable, DropsDigitalAsset {
    event Minted(address indexed recipient, bytes32[] tokenIds, uint256 totalPrice);
    event DefaultTokenDataChanged(bytes defaultTokenData);

    uint256 private constant _LSP8_TOKEN_ID_TYPE_UNIQUE_NUMBER = 0;

    bytes32 private constant _LSP8_TOKEN_METADATA_BASE_URI_KEY =
        0x1a7628600c3bac7101f53697f48df381ddc36b9015e7d7c9c5633d1252aa2843;

    bytes32 private constant _LSP8_TOKEN_URI_DATA_KEY_PREFIX =
        0x1339e76a390b7b9ec90100000000000000000000000000000000000000000000;

    bytes public defaultTokenUri;
    uint256 private _totalMintedTokens;

    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        address service_,
        address verifier_,
        uint256 tokenSupplyCap_,
        uint32 serviceFeePoints_
    )
        LSP8IdentifiableDigitalAsset(name_, symbol_, newOwner_, _LSP8_TOKEN_ID_TYPE_UNIQUE_NUMBER)
        LSP8CappedSupply(tokenSupplyCap_)
        DropsDigitalAsset(service_, verifier_, serviceFeePoints_)
    {
        // noop
    }

    function setDefaultTokenUri(bytes calldata newTokenUri) external onlyOwner {
        defaultTokenUri = newTokenUri;
        emit DefaultTokenDataChanged(newTokenUri);
    }

    function _getData(bytes32 dataKey) internal view override returns (bytes memory) {
        bytes memory result = super._getData(dataKey);
        if ((result.length == 0) && ((dataKey & _LSP8_TOKEN_URI_DATA_KEY_PREFIX) == _LSP8_TOKEN_URI_DATA_KEY_PREFIX)) {
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
        for (uint256 i = 0; i < amount;) {
            tokenIds[i] = bytes32(firstTokenId + i);
            unchecked {
                i++;
            }
        }
        emit Minted(recipient, tokenIds, totalPrice);
        // mint tokens
        for (uint256 i = 0; i < amount;) {
            _mint(recipient, tokenIds[i], false, "");
            unchecked {
                i++;
            }
        }
    }

    function balanceOf(address tokenOwner)
        public
        view
        virtual
        override(LSP8IdentifiableDigitalAssetCore, DropsDigitalAsset)
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
