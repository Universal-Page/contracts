// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

abstract contract IndexedDrop {
    error ClaimingUnavailable();
    error InvalidClaim(uint256 index, bytes data);
    error AlreadyClaimed(uint256 index, bytes data);

    bytes32 private _root;
    mapping(uint256 => uint256) private _claimed;

    function root() internal view returns (bytes32) {
        return _root;
    }

    function _hasRoot() internal view returns (bool) {
        return _root != 0;
    }

    function _setRoot(bytes32 newRoot) internal {
        _root = newRoot;
    }

    function _isClaimed(uint256 index) internal view returns (bool) {
        uint256 slotIndex = index / 256;
        uint256 slotOffset = index % 256;
        uint256 value = 1 << slotOffset;
        return _claimed[slotIndex] & value == value;
    }

    function _markClaimed(uint256 index) private {
        uint256 slotIndex = index / 256;
        uint256 slotOffset = index % 256;
        _claimed[slotIndex] = _claimed[slotIndex] | (1 << slotOffset);
    }

    function _claim(bytes32[] memory proof, uint256 index, bytes memory data) internal {
        if (!_hasRoot()) {
            revert ClaimingUnavailable();
        }
        if (_isClaimed(index)) {
            revert AlreadyClaimed(index, data);
        }
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index, data))));
        if (!MerkleProof.verify(proof, _root, leaf)) {
            revert InvalidClaim(index, data);
        }
        _markClaimed(index);
    }
}
