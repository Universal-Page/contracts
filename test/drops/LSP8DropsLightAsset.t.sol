// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {IndexedDrop} from "../../src/common/IndexedDrop.sol";
import {LSP8DropsLightAsset, DropsLightAsset} from "../../src/drops/LSP8DropsLightAsset.sol";
import {deployProfile} from "../utils/profile.sol";

contract LSP8DropsLightAssetTest is Test {
    event Activated();
    event Deactivated();
    event Claimed(address indexed account, address indexed recipient, uint256 amount);
    event Minted(address indexed recipient, bytes32[] tokenIds, uint256 totalPrice);
    event ConfigurationChanged(uint256 startTime, uint256 mintPrice, uint256 profileMintLimit);
    event DefaultTokenDataChanged(bytes defaultTokenData);

    LSP8DropsLightAsset drop;
    address owner;
    address beneficiary;
    address service;
    uint256 verifierKey;
    address verifier;

    function setUp() public {
        owner = vm.addr(1);
        service = vm.addr(2);
        beneficiary = vm.addr(3);
        verifierKey = 3;
        verifier = vm.addr(verifierKey);

        vm.warp(block.timestamp + 7 days);

        drop = new LSP8DropsLightAsset("Drops", "DRP", owner, beneficiary, service, verifier, 10, 10_000);
    }

    function test_Initialize() public {
        assertEq("Drops", drop.getData(_LSP4_TOKEN_NAME_KEY));
        assertEq("DRP", drop.getData(_LSP4_TOKEN_SYMBOL_KEY));
        assertEq(owner, drop.owner());
        assertEq(beneficiary, drop.beneficiary());
        assertEq(service, drop.service());
        assertEq(verifier, drop.verifier());
        assertEq(10, drop.tokenSupplyCap());
        assertEq(10_000, drop.serviceFeePoints());
    }

    function test_ConfigureIfOwner() public {
        vm.expectEmit(address(drop));
        emit DefaultTokenDataChanged(new bytes(0));
        vm.prank(owner);
        drop.setDefaultTokenUri(new bytes(0));
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        drop.setDefaultTokenUri(new bytes(0));
    }

    function test_Mint() public {
        (UniversalProfile profile,) = deployProfile();

        assertEq(drop.mintNonceOf(address(profile)), 0);

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(drop),
                block.chainid,
                address(profile),
                drop.mintNonceOf(address(profile)),
                uint256(3),
                uint256(3 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        vm.expectEmit(address(drop));
        bytes32[] memory tokenIds = new bytes32[](3);
        tokenIds[0] = bytes32(uint256(1));
        tokenIds[1] = bytes32(uint256(2));
        tokenIds[2] = bytes32(uint256(3));
        emit Minted(address(profile), tokenIds, 3 ether);
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        assertEq(drop.mintNonceOf(address(profile)), 1);
        assertEq(drop.totalSupply(), 3);
        assertEq(drop.balanceOf(address(profile)), 3);
        assertEq(drop.tokenOwnerOf(tokenIds[0]), address(profile));
        assertEq(drop.tokenOwnerOf(tokenIds[1]), address(profile));
        assertEq(drop.tokenOwnerOf(tokenIds[2]), address(profile));
        assertEq(drop.claimBalanceOf(owner), 0 ether);
        assertEq(drop.claimBalanceOf(beneficiary), 2.7 ether);
        assertEq(drop.claimBalanceOf(service), 0.3 ether);
    }

    function test_Revert_MintIfReuseSignature() public {
        (UniversalProfile profile,) = deployProfile();

        assertEq(drop.mintNonceOf(address(profile)), 0);

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(drop),
                block.chainid,
                address(profile),
                drop.mintNonceOf(address(profile)),
                uint256(3),
                uint256(3 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        vm.expectEmit(address(drop));
        bytes32[] memory tokenIds = new bytes32[](3);
        tokenIds[0] = bytes32(uint256(1));
        tokenIds[1] = bytes32(uint256(2));
        tokenIds[2] = bytes32(uint256(3));
        emit Minted(address(profile), tokenIds, 3 ether);
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(DropsLightAsset.MintInvalidSignature.selector));
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        assertEq(drop.mintNonceOf(address(profile)), 1);
        assertEq(drop.totalSupply(), 3);
        assertEq(drop.balanceOf(address(profile)), 3);
        assertEq(drop.tokenOwnerOf(tokenIds[0]), address(profile));
        assertEq(drop.tokenOwnerOf(tokenIds[1]), address(profile));
        assertEq(drop.tokenOwnerOf(tokenIds[2]), address(profile));
        assertEq(drop.claimBalanceOf(owner), 0 ether);
        assertEq(drop.claimBalanceOf(beneficiary), 2.7 ether);
        assertEq(drop.claimBalanceOf(service), 0.3 ether);
    }

    function test_Revert_MintIfNotAuthorized() public {
        (UniversalProfile profile,) = deployProfile();

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(drop),
                block.chainid,
                address(profile),
                drop.mintNonceOf(address(profile)),
                uint256(2),
                uint256(2 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 2 ether);
        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(DropsLightAsset.MintInvalidSignature.selector));
        drop.mint{value: 2 ether}(address(profile), 4, v, r, s);
    }

    function test_Revert_MintIfInvalidSigner() public {
        (UniversalProfile profile,) = deployProfile();

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(drop),
                block.chainid,
                address(profile),
                drop.mintNonceOf(address(profile)),
                uint256(2),
                uint256(2 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(100, hash);

        vm.deal(address(profile), 2 ether);
        vm.prank(address(profile));
        vm.expectRevert(abi.encodeWithSelector(DropsLightAsset.MintInvalidSignature.selector));
        drop.mint{value: 2 ether}(address(profile), 2, v, r, s);
    }

    function test_Claim() public {
        (UniversalProfile profile,) = deployProfile();

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(drop),
                block.chainid,
                address(profile),
                drop.mintNonceOf(address(profile)),
                uint256(3),
                uint256(3 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        assertEq(drop.claimBalanceOf(beneficiary), 2.7 ether);
        assertEq(drop.claimBalanceOf(service), 0.3 ether);

        address recipient = address(100);

        vm.prank(beneficiary);
        vm.expectEmit(address(drop));
        emit Claimed(beneficiary, recipient, 2.7 ether);
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

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(drop),
                block.chainid,
                address(profile),
                drop.mintNonceOf(address(profile)),
                uint256(3),
                uint256(3 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verifierKey, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        drop.mint{value: 3 ether}(address(profile), 3, v, r, s);

        assertEq(drop.claimBalanceOf(beneficiary), 2.7 ether);
        assertEq(drop.claimBalanceOf(service), 0.3 ether);

        address recipient = address(100);

        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSelector(DropsLightAsset.ClaimInvalidAmount.selector, 1 ether));
        drop.claim(recipient, 1 ether);
    }

    function test_DefaultTokenUri() public {
        vm.prank(owner);
        drop.setDefaultTokenUri(bytes.concat(bytes4(0), "http://test/default"));

        bytes32 tokenId = bytes32(uint256(1));
        bytes32 tokenUriKey = keccak256(bytes("LSP4Metadata"));

        assertEq(bytes.concat(bytes4(0), "http://test/default"), drop.getDataForTokenId(tokenId, tokenUriKey));
    }

    function test_DefaultTokenUriOverridenByBaseUri() public {
        vm.prank(owner);
        drop.setDefaultTokenUri(bytes.concat(bytes4(0), "http://test/default"));

        bytes32 tokenId = bytes32(uint256(1));
        bytes32 tokenUriKey = keccak256(bytes("LSP4Metadata"));
        assertEq(bytes.concat(bytes4(0), "http://test/default"), drop.getDataForTokenId(tokenId, tokenUriKey));

        vm.prank(owner);
        drop.setData(keccak256(bytes("LSP8TokenMetadataBaseURI")), bytes.concat(bytes4(0), "http://test/base/"));

        assertEq(
            bytes.concat(bytes4(0), "http://test/base/"), drop.getData(keccak256(bytes("LSP8TokenMetadataBaseURI")))
        );
        assertEq(new bytes(0), drop.getDataForTokenId(tokenId, tokenUriKey));
    }
}
