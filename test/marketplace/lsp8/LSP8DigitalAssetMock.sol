// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {LSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";

contract LSP8DigitalAssetMock is LSP8IdentifiableDigitalAsset {
    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        uint256 tokenIdType_,
        uint256 lsp8TokenIdSchema_
    ) LSP8IdentifiableDigitalAsset(name_, symbol_, newOwner_, tokenIdType_, lsp8TokenIdSchema_) {
        // noop
    }

    function mint(address to, bytes32 tokenId, bool allowNonLSP1Recipient, bytes memory data) external {
        _mint(to, tokenId, allowNonLSP1Recipient, data);
    }
}
