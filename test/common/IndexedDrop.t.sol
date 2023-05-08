// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {AssetDropMock} from "./AssetDropMock.sol";
import {IndexedDrop} from "../../src/common/IndexedDrop.sol";

contract IndexedDropTest is Test {
    AssetDropMock drop;
    Merkle merkle;

    function setUp() public {
        drop = new AssetDropMock();
        merkle = new Merkle();
    }

    function testFuzz_Claim(address alice, address bob, uint256 amount1, uint256 amount2, uint256 amount3) public {
        bytes32[] memory data = new bytes32[](3);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(alice, amount1)))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(alice, amount2)))));
        data[2] = keccak256(bytes.concat(keccak256(abi.encode(uint256(2), abi.encode(bob, amount3)))));
        drop.setup(merkle.getRoot(data));

        drop.claim(merkle.getProof(data, 0), 0, alice, amount1);
        assertTrue(drop.isClaimed(0));
        drop.claim(merkle.getProof(data, 1), 1, alice, amount2);
        assertTrue(drop.isClaimed(1));
        drop.claim(merkle.getProof(data, 2), 2, bob, amount3);
        assertTrue(drop.isClaimed(2));
    }

    function test_Revert_IfClaimed() public {
        address alice = vm.addr(1);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(alice, uint256(1 ether))))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(alice, uint256(1.5 ether))))));
        drop.setup(merkle.getRoot(data));

        drop.claim(merkle.getProof(data, 0), 0, alice, 1 ether);
        assertTrue(drop.isClaimed(0));

        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IndexedDrop.AlreadyClaimed.selector, 0, abi.encode(alice, uint256(1 ether)))
        );
        drop.claim(proof, 0, alice, 1 ether);
    }

    function test_Revert_IfInvalidClaim() public {
        address alice = vm.addr(1);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(alice, uint256(1 ether))))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(alice, uint256(1.5 ether))))));
        drop.setup(merkle.getRoot(data));

        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IndexedDrop.InvalidClaim.selector, 0, abi.encode(alice, uint256(2 ether)))
        );
        drop.claim(proof, 0, alice, 2 ether);
    }
}
