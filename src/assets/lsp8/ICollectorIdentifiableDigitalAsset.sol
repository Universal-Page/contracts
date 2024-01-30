// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";

interface ICollectorIdentifiableDigitalAsset is ILSP8IdentifiableDigitalAsset {
    /// A tier of a token if any. A tier is a number from 0 to 3. 3 is the highest tier.
    /// @param tokenId A token id to get a tier for.
    function tokenTierOf(bytes32 tokenId) external view returns (uint8 tier);

    /// An index of a token.
    /// @param tokenId A token id to get an index for.
    function tokenIndexOf(bytes32 tokenId) external view returns (uint16 index);

    /// Purchases tokens from the contract and transfers them to a recipient.
    /// Amount paid must be equal to the price multipled by the number of tokens.
    /// @param recipient A recipient of tokens.
    /// @param tokenIds A list of token ids to purchase.
    /// @param v A signature v.
    /// @param r A signature r.
    /// @param s A signature s.
    function purchase(address recipient, bytes32[] calldata tokenIds, uint8 v, bytes32 r, bytes32 s) external payable;
}
