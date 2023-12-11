// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

struct PendingSale {
    address asset;
    bytes32 tokenId;
    address seller;
    address buyer;
    uint256 totalPaid;
}

interface IPageNameMarketplace {
    /// a pending sale that is currently being transacted.
    function pendingSale() external view returns (PendingSale memory);
}
