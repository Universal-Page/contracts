// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {IndexedDrop} from "../../src/common/IndexedDrop.sol";

contract AssetDropMock is IndexedDrop {
    function isSetup() external view returns (bool) {
        return _hasRoot();
    }

    function setup(bytes32 root) external {
        _setRoot(root);
    }

    function isClaimed(uint256 index) external view returns (bool) {
        return _isClaimed(index);
    }

    function claim(bytes32[] memory proof, uint256 index, address recipient, uint256 amount) external {
        _claim(proof, index, abi.encode(recipient, amount));
    }
}
