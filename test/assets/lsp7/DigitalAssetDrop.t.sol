// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {DigitalAssetDrop} from "../../../src/assets/lsp7/DigitalAssetDrop.sol";
import {deployProfile} from "../../utils/profile.sol";
import {DigitalAssetMock} from "./DigitalAssetMock.sol";

contract DigitalAssetDropTest is Test {
    event Claimed(uint256 indexed index, address indexed recipient, uint256 amount);
    event Disposed(address indexed beneficiary, uint256 amount);

    Merkle merkle;
    address assetOwner;
    address profileOwner;
    address dropOwner;
    DigitalAssetMock asset;

    function setUp() public {
        assetOwner = vm.addr(1);
        profileOwner = vm.addr(2);
        dropOwner = vm.addr(3);

        merkle = new Merkle();
        asset = new DigitalAssetMock("Mock", "MCK", assetOwner, _LSP4_TOKEN_TYPE_NFT, true);
    }

    function test_Claim() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(alice, uint256(3))))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(bob, uint256(5))))));

        DigitalAssetDrop drop = new DigitalAssetDrop(asset, merkle.getRoot(data), dropOwner);
        asset.mint(address(drop), 8, true, "");
        assertEq(asset.balanceOf(address(drop)), 8);

        vm.startPrank(address(alice));
        vm.expectEmit(address(drop));
        emit Claimed(0, address(alice), 3);
        drop.claim(merkle.getProof(data, 0), 0, address(alice), 3);
        vm.stopPrank();

        vm.startPrank(address(bob));
        vm.expectEmit(address(drop));
        emit Claimed(1, address(bob), 5);
        drop.claim(merkle.getProof(data, 1), 1, address(bob), 5);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(drop)), 0);
        assertEq(asset.balanceOf(address(alice)), 3);
        assertEq(asset.balanceOf(address(bob)), 5);
    }

    function test_ClaimToRecipient() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(alice, uint256(3))))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(alice, uint256(5))))));

        DigitalAssetDrop drop = new DigitalAssetDrop(asset, merkle.getRoot(data), dropOwner);
        asset.mint(address(drop), 8, true, "");
        assertEq(asset.balanceOf(address(drop)), 8);

        vm.startPrank(address(alice));

        vm.expectEmit(address(drop));
        emit Claimed(0, address(bob), 3);
        drop.claim(merkle.getProof(data, 0), 0, address(bob), 3);

        vm.expectEmit(address(drop));
        emit Claimed(1, address(bob), 5);
        drop.claim(merkle.getProof(data, 1), 1, address(bob), 5);

        vm.stopPrank();

        assertEq(asset.balanceOf(address(drop)), 0);
        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(asset.balanceOf(address(bob)), 8);
    }

    function test_Dispose() public {
        address beneficiary = vm.addr(100);
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(alice, uint256(3))))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(bob, uint256(5))))));

        DigitalAssetDrop drop = new DigitalAssetDrop(asset, merkle.getRoot(data), dropOwner);
        asset.mint(address(drop), 8, true, "");
        assertEq(asset.balanceOf(address(drop)), 8);

        assertEq(asset.balanceOf(beneficiary), 0);
        vm.prank(dropOwner);
        vm.expectEmit(address(drop));
        emit Disposed(beneficiary, 8);
        drop.dispose(beneficiary);
        assertEq(asset.balanceOf(address(drop)), 0);
        assertEq(asset.balanceOf(beneficiary), 8);
    }

    function test_Revert_DisposeIfNotOwner() public {
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(address(1), uint256(3))))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(address(1), uint256(5))))));

        DigitalAssetDrop drop = new DigitalAssetDrop(asset, merkle.getRoot(data), dropOwner);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        drop.dispose(address(1));
    }
}
