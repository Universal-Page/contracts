// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

interface IParticipant {
    /// Calculates a discount points for a fee on a marketplace.
    /// @param profile a universal profile to calculate a discount for
    function feeDiscountFor(address profile) external view returns (uint32);
}
