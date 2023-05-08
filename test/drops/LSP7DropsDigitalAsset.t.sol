// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {IndexedDrop} from "../../src/common/IndexedDrop.sol";
import {LSP7DropsDigitalAsset, DropsDigitalAsset} from "../../src/drops/LSP7DropsDigitalAsset.sol";
import {deployProfile} from "../utils/profile.sol";

contract LSP7DropsDigitalAssetTest is Test {
    event Activated();
    event Deactivated();
    event Claimed(address indexed account, address indexed beneficiary, uint256 amount);
    event Minted(address indexed recipient, uint256 amount, uint256 totalPrice);
    event ConfigurationChanged(uint256 startTime, uint256 mintPrice, uint256 profileMintLimit, bytes32 allowlistRoot);

    Merkle merkle;
    LSP7DropsDigitalAsset drop;
    address owner;
    address service;
    uint256 verifierKey;
    address verifier;

    function setUp() public {
        owner = vm.addr(1);
        service = vm.addr(2);
        verifierKey = 3;
        verifier = vm.addr(verifierKey);
        merkle = new Merkle();

        vm.warp(block.timestamp + 7 days);

        drop = new LSP7DropsDigitalAsset("Drops", "DRP", owner, service, verifier, 10, 10_000);
    }

    function test_Initialize() public {
        assertFalse(drop.activated());
        assertEq("Drops", drop.getData(_LSP4_TOKEN_NAME_KEY));
        assertEq("DRP", drop.getData(_LSP4_TOKEN_SYMBOL_KEY));
        assertEq(owner, drop.owner());
        assertEq(service, drop.service());
        assertEq(verifier, drop.verifier());
        assertEq(10, drop.tokenSupplyCap());
        assertEq(10_000, drop.serviceFeePoints());
        assertEq(0, drop.profileMintLimit());
        assertEq(0, drop.mintPrice());
        assertEq(0, drop.startTime());
    }

    function test_ConfigureIfOwner() public {
        vm.expectEmit(address(drop));
        emit ConfigurationChanged(block.timestamp + 1 days, 1 ether, 3, 0);
        vm.prank(owner);
        drop.configure(block.timestamp + 1 days, 1 ether, 3, 0);
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        drop.configure(block.timestamp + 1 days, 1 ether, 3, 0);
    }

    function test_Mint() public {
        (UniversalProfile profile,) = deployProfile();

        vm.prank(owner);
        drop.activate();

        vm.prank(owner);
        drop.configure(block.timestamp, 1 ether, 3, 0);

        bytes32 hash =
            keccak256(abi.encodePacked(address(drop), block.chainid, address(profile), uint256(3), uint256(3 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        vm.expectEmit(address(drop));
        emit Minted(address(profile), 3, 3 ether);
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        assertEq(drop.totalSupply(), 3);
        assertEq(drop.balanceOf(address(profile)), 3);
    }

    function test_Revert_MintIfInactive() public {
        (UniversalProfile profile,) = deployProfile();

        bytes32 hash =
            keccak256(abi.encodePacked(address(drop), block.chainid, address(profile), uint256(3), uint256(3 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(DropsDigitalAsset.Inactive.selector));
        drop.mint(address(profile), 3, v, r, s);

        vm.prank(owner);
        drop.configure(block.timestamp, 1 ether, 3, 0);

        vm.warp(block.timestamp - 10 seconds);
        vm.prank(owner);
        drop.activate();

        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(DropsDigitalAsset.Inactive.selector));
        drop.mint(address(profile), 3, v, r, s);
    }

    function test_Revert_MintIfNotAuthorized() public {
        (UniversalProfile profile,) = deployProfile();

        vm.prank(owner);
        drop.activate();

        vm.prank(owner);
        drop.configure(block.timestamp, 1 ether, 3, 0);

        bytes32 hash =
            keccak256(abi.encodePacked(address(drop), block.chainid, address(profile), uint256(2), uint256(2 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 2 ether);
        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(DropsDigitalAsset.MintInvalidSignature.selector));
        drop.mint{value: 2 ether}(address(profile), 4, v, r, s);
    }

    function test_Revert_MintIfInvalidSigner() public {
        (UniversalProfile profile,) = deployProfile();

        vm.prank(owner);
        drop.activate();

        vm.prank(owner);
        drop.configure(block.timestamp, 1 ether, 3, 0);

        bytes32 hash =
            keccak256(abi.encodePacked(address(drop), block.chainid, address(profile), uint256(2), uint256(2 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(100, hash);

        vm.deal(address(profile), 2 ether);
        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(DropsDigitalAsset.MintInvalidSignature.selector));
        drop.mint{value: 2 ether}(address(profile), 2, v, r, s);
    }

    function test_MintAllowlist() public {
        (UniversalProfile alice,) = deployProfile();

        bytes32[] memory allowlist = new bytes32[](2);
        allowlist[0] = keccak256(bytes.concat(keccak256(abi.encode(uint256(0), abi.encode(alice)))));
        allowlist[1] = keccak256(bytes.concat(keccak256(abi.encode(uint256(1), abi.encode(address(100))))));
        bytes32 allowlistRoot = merkle.getRoot(allowlist);

        vm.prank(owner);
        drop.activate();

        vm.prank(owner);
        drop.configure(block.timestamp, 1 ether, 2, allowlistRoot);

        bytes32 hash =
            keccak256(abi.encodePacked(address(drop), block.chainid, address(alice), uint256(2), uint256(2 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(alice), 2 ether);
        vm.startPrank(address(alice));
        vm.expectEmit(address(drop));
        emit Minted(address(alice), 2, 2 ether);
        drop.mintAllowlist{value: 2 ether}(merkle.getProof(allowlist, 0), 0, address(alice), 2, v, r, s);
        vm.stopPrank();

        assertEq(drop.totalSupply(), 2);
        assertEq(drop.balanceOf(address(alice)), 2);
    }

    function test_Claim() public {
        (UniversalProfile profile,) = deployProfile();

        vm.prank(owner);
        drop.activate();

        vm.prank(owner);
        drop.configure(block.timestamp, 1 ether, 3, 0);

        bytes32 hash =
            keccak256(abi.encodePacked(address(drop), block.chainid, address(profile), uint256(3), uint256(3 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        assertEq(drop.claimBalanceOf(owner), 2.7 ether);
        assertEq(drop.claimBalanceOf(service), 0.3 ether);

        address recipient = address(100);

        vm.prank(owner);
        vm.expectEmit(address(drop));
        emit Claimed(owner, recipient, 2.7 ether);
        drop.claim(recipient, 2.7 ether);
        assertEq(recipient.balance, 2.7 ether);

        vm.prank(service);
        vm.expectEmit(address(drop));
        emit Claimed(service, recipient, 0.3 ether);
        drop.claim(recipient, 0.3 ether);
        assertEq(recipient.balance, 3 ether);
    }

    function test_Revert_Claim() public {
        (UniversalProfile profile,) = deployProfile();

        vm.prank(owner);
        drop.activate();

        vm.prank(owner);
        drop.configure(block.timestamp, 1 ether, 3, 0);

        bytes32 hash =
            keccak256(abi.encodePacked(address(drop), block.chainid, address(profile), uint256(3), uint256(3 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        assertEq(drop.claimBalanceOf(owner), 2.7 ether);
        assertEq(drop.claimBalanceOf(service), 0.3 ether);

        address recipient = address(100);

        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSelector(DropsDigitalAsset.ClaimInvalidAmount.selector, 1 ether));
        drop.claim(recipient, 1 ether);
    }
}
