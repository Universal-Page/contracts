// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

library Points {
    uint32 public constant BASIS = 100_000;

    function isValid(uint32 points) external pure returns (bool) {
        return points <= BASIS;
    }

    function multiply(uint32 one, uint32 other) external pure returns (uint32) {
        return (one * other) / BASIS;
    }

    function realize(uint256 value, uint32 points) external pure returns (uint256) {
        return (value * points) / BASIS;
    }
}
