// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY,
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_TOKEN_TYPE_NFT
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {
    _LSP8_TOKENID_FORMAT_KEY,
    _LSP8_TOKENID_FORMAT_UNIQUE_ID
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {CollectorIdentifiableDigitalAsset} from "../../../src/assets/lsp8/CollectorIdentifiableDigitalAsset.sol";
import {deployProfile} from "../../utils/profile.sol";

contract CollectorIdentifiableDigitalAssetTest is Test {
    event TokensPurchased(address indexed recipient, bytes32[] tokenIds, uint256 totalPaid);
    event TokensReserved(address indexed recipient, bytes32[] tokenIds);
    event ControllerChanged(address indexed oldController, address indexed newController);

    address owner;
    uint256 controllerKey;
    address controller;
    CollectorIdentifiableDigitalAsset asset;

    function setUp() public {
        owner = vm.addr(1);
        controllerKey = 2;
        controller = vm.addr(controllerKey);

        asset = new CollectorIdentifiableDigitalAsset("Universal Page Collector", "UPC", owner, controller, 100);
    }

    function test_Initialize() public {
        assertEq("Universal Page Collector", asset.getData(_LSP4_TOKEN_NAME_KEY));
        assertEq("UPC", asset.getData(_LSP4_TOKEN_SYMBOL_KEY));
        assertEq(_LSP4_TOKEN_TYPE_NFT, uint256(bytes32(asset.getData(_LSP4_TOKEN_TYPE_KEY))));
        assertEq(_LSP8_TOKENID_FORMAT_UNIQUE_ID, uint256(bytes32(asset.getData(_LSP8_TOKENID_FORMAT_KEY))));
        assertEq(0, asset.totalSupply());
        assertEq(100, asset.tokenSupplyCap());
        assertEq(owner, asset.owner());
        assertEq(controller, asset.controller());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        asset.setController(address(10));
        vm.stopPrank();
    }

    function test_Revert_IfNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        asset.setController(address(100));

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        asset.withdraw(0 ether);
    }

    function test_Revert_PurchaseIfUnathorized() public {
        (UniversalProfile profile,) = deployProfile();

        bytes32[] memory tokenIds = new bytes32[](3);
        tokenIds[0] = bytes32(uint256(1));
        tokenIds[1] = bytes32(uint256(2));
        tokenIds[2] = bytes32(uint256(3));

        bytes32 hash =
            keccak256(abi.encodePacked(address(asset), block.chainid, address(profile), tokenIds, uint256(3 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(100, hash);

        vm.deal(address(profile), 3 ether);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectorIdentifiableDigitalAsset.UnauthorizedPurchase.selector, address(profile), tokenIds, 3 ether
            )
        );
        asset.purchase{value: 3 ether}(address(profile), tokenIds, v, r, s);
    }

    function test_Revert_PurchaseIfTokenIndexAlreadyMinted() public {
        (UniversalProfile profile,) = deployProfile();

        for (uint256 tier = 1; tier <= 3; tier++) {
            bytes32[] memory tokenIds = new bytes32[](2);
            tokenIds[0] = bytes32(uint256(0x10));
            tokenIds[1] = bytes32(uint256(0x10 + tier));

            bytes32 hash =
                keccak256(abi.encodePacked(address(asset), block.chainid, address(profile), tokenIds, uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);

            vm.prank(address(profile));
            vm.expectRevert(
                abi.encodeWithSelector(CollectorIdentifiableDigitalAsset.InvalidTokenId.selector, tokenIds[1])
            );
            asset.purchase(address(profile), tokenIds, v, r, s);
        }
    }

    function testFuzz_Purchase(bytes32 tokenId0, bytes32 tokenId1, bytes32 tokenId2, uint256 price) public {
        vm.assume(
            uint16((uint256(tokenId0) >> 4) & 0xFFFF) != uint16((uint256(tokenId1) >> 4) & 0xFFFF)
                && uint16((uint256(tokenId0) >> 4) & 0xFFFF) != uint16((uint256(tokenId2) >> 4) & 0xFFFF)
                && uint16((uint256(tokenId1) >> 4) & 0xFFFF) != uint16((uint256(tokenId2) >> 4) & 0xFFFF)
        );
        vm.assume(price <= 10 ether);

        bytes32[] memory tokenIds = new bytes32[](3);
        tokenIds[0] = tokenId0;
        tokenIds[1] = tokenId1;
        tokenIds[2] = tokenId2;

        (UniversalProfile profile,) = deployProfile();

        bytes32 hash = keccak256(
            abi.encodePacked(address(asset), block.chainid, address(profile), tokenIds, price * tokenIds.length)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);

        vm.deal(address(profile), price * tokenIds.length);
        vm.prank(address(profile));
        vm.expectEmit(address(asset));
        emit TokensPurchased(address(profile), tokenIds, price * tokenIds.length);
        asset.purchase{value: price * tokenIds.length}(address(profile), tokenIds, v, r, s);

        assertEq(tokenIds.length, asset.totalSupply());
        assertEq(tokenIds.length, asset.balanceOf(address(profile)));
        assertEq(address(profile), asset.tokenOwnerOf(tokenId0));
        assertEq(address(profile), asset.tokenOwnerOf(tokenId1));
        assertEq(address(profile), asset.tokenOwnerOf(tokenId2));
    }

    function test_TokenIdentifiers() public {
        bytes32[] memory tokenIds = new bytes32[](4);
        tokenIds[0] = bytes32(uint256((1 << 4) | 0));
        tokenIds[1] = bytes32(uint256((2 << 4) | 1));
        tokenIds[2] = bytes32(uint256((3 << 4) | 2));
        tokenIds[3] = bytes32(uint256((4 << 4) | 3));

        address recipient = vm.addr(1000);

        bytes32 hash = keccak256(abi.encodePacked(address(asset), block.chainid, recipient, tokenIds, uint256(0 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);

        vm.prank(recipient);
        asset.purchase(recipient, tokenIds, v, r, s);

        assertEq(4, asset.totalSupply());
        assertEq(0, asset.tokenTierOf(tokenIds[0]));
        assertEq(1, asset.tokenIndexOf(tokenIds[0]));
        assertEq(1, asset.tokenTierOf(tokenIds[1]));
        assertEq(2, asset.tokenIndexOf(tokenIds[1]));
        assertEq(2, asset.tokenTierOf(tokenIds[2]));
        assertEq(3, asset.tokenIndexOf(tokenIds[2]));
        assertEq(3, asset.tokenTierOf(tokenIds[3]));
        assertEq(4, asset.tokenIndexOf(tokenIds[3]));
    }
}
