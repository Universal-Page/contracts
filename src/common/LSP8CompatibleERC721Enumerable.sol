// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Enumerable, IERC721} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {
    LSP8IdentifiableDigitalAsset,
    LSP8IdentifiableDigitalAssetCore
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {LSP8Enumerable} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8Enumerable.sol";

abstract contract LSP8CompatibleERC721Enumerable is IERC721Enumerable, LSP8Enumerable {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, LSP8IdentifiableDigitalAsset)
        returns (bool)
    {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    function totalSupply()
        public
        view
        virtual
        override(IERC721Enumerable, LSP8IdentifiableDigitalAssetCore)
        returns (uint256)
    {
        return _existingTokens;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view override returns (uint256) {
        bytes32[] memory tokenIds = tokenIdsOf(owner);
        return uint256(tokenIds[index]);
    }

    function tokenByIndex(uint256 index) public view override returns (uint256) {
        return uint256(tokenAt(index));
    }

    function balanceOf(address tokenOwner)
        public
        view
        virtual
        override(IERC721, LSP8IdentifiableDigitalAssetCore)
        returns (uint256)
    {
        return super.balanceOf(tokenOwner);
    }
}
