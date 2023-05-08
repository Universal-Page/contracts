// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {CollectorIdentifiableDigitalAsset} from "../../../src/assets/lsp8/CollectorIdentifiableDigitalAsset.sol";
import {deployProfile} from "../../utils/profile.sol";

bytes32 constant _LSP8_TOKEN_ID_TYPE_KEY = 0x715f248956de7ce65e94d9d836bfead479f7e70d69b718d47bfe7b00e05b4fe4;

contract CollectorIdentifiableDigitalAssetTest is Test {
    event TokensPurchased(address indexed recipient, bytes32[] tokenIds, uint256 totalPaid);
    event TokenSupplyLimitChanged(uint256 limit);
    event PriceChanged(uint256 price);
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
        assertEq(2, /* unuque identifier/sequence */ uint256(bytes32(asset.getData(_LSP8_TOKEN_ID_TYPE_KEY))));
        assertEq(0, asset.totalSupply());
        assertEq(100, asset.tokenSupplyCap());
        assertEq(0, asset.tokenSupplyLimit());
        assertEq(0, asset.price());
        assertEq(owner, asset.owner());
        assertEq(controller, asset.controller());
        assertFalse(asset.paused());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        asset.setPrice(1 ether);
        asset.setController(address(10));
        asset.pause();
        asset.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        asset.setPrice(0 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        asset.setController(address(100));
        vm.expectRevert("Ownable: caller is not the owner");
        asset.pause();
        vm.expectRevert("Ownable: caller is not the owner");
        asset.unpause();
        vm.expectRevert("Ownable: caller is not the owner");
        asset.withdraw(0 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        bytes32[] memory tokenIds = new bytes32[](1);
        tokenIds[0] = bytes32(uint256(1));
        asset.reserve(address(100), tokenIds);
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        asset.pause();
        vm.expectRevert("Pausable: paused");
        bytes32[] memory tokenIds = new bytes32[](1);
        tokenIds[0] = bytes32(uint256(1));
        asset.purchase(address(100), tokenIds, 0, 0, 0);
    }

    function testFuzz_TokenId(uint256 index, uint256 tier) public {
        vm.assume(tier <= 3);
        vm.assume(index <= 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        bytes32 tokenId = bytes32((index << 4) | tier);

        bytes32[] memory tokenIds = new bytes32[](1);
        tokenIds[0] = tokenId;

        vm.startPrank(owner);
        asset.setTokenSupplyLimit(1);
        asset.reserve(address(100), tokenIds);
        vm.stopPrank();

        assertEq(asset.tokenIndexOf(tokenId), index);
        assertEq(asset.tokenTierOf(tokenId), tier);
    }

    function test_Revert_PurchaseIfUnathorized() public {
        (UniversalProfile profile,) = deployProfile();

        vm.startPrank(owner);
        asset.setPrice(1 ether);
        asset.setTokenSupplyLimit(3);
        vm.stopPrank();

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

        vm.startPrank(owner);
        asset.setTokenSupplyLimit(2);
        vm.stopPrank();

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

    function test_Revert_PurchaseIfTokenLimitExceeded() public {
        (UniversalProfile profile,) = deployProfile();

        vm.startPrank(owner);
        asset.setPrice(1 ether);
        asset.setTokenSupplyLimit(2);
        vm.stopPrank();

        bytes32[] memory tokenIds = new bytes32[](3);
        tokenIds[0] = bytes32(uint256(0x10));
        tokenIds[1] = bytes32(uint256(0x11));
        tokenIds[2] = bytes32(uint256(0x31));

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(asset), block.chainid, address(profile), tokenIds, uint256(1 ether * tokenIds.length)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);

        vm.deal(address(profile), 1 ether * tokenIds.length);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectorIdentifiableDigitalAsset.TokenSupplyLimitExceeded.selector, 0, 2, tokenIds.length
            )
        );
        asset.purchase{value: 1 ether * tokenIds.length}(address(profile), tokenIds, v, r, s);
    }

    function testFuzz_Purchase(bytes32 tokenId0, bytes32 tokenId1, bytes32 tokenId2, uint256 price, uint256 supplyLimit)
        public
    {
        vm.assume(
            ((uint256(tokenId0) >> 4) != (uint256(tokenId1) >> 4))
                && ((uint256(tokenId0) >> 4) != (uint256(tokenId2) >> 4))
                && ((uint256(tokenId1) >> 4) != (uint256(tokenId2) >> 4))
        );
        vm.assume(supplyLimit >= 3 && supplyLimit <= asset.tokenSupplyCap());
        vm.assume(price <= 10 ether);

        bytes32[] memory tokenIds = new bytes32[](3);
        tokenIds[0] = tokenId0;
        tokenIds[1] = tokenId1;
        tokenIds[2] = tokenId2;

        (UniversalProfile profile,) = deployProfile();

        vm.startPrank(owner);
        asset.setPrice(price);
        asset.setTokenSupplyLimit(supplyLimit);
        vm.stopPrank();

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

    function testFuzz_Reserve(bytes32 tokenId0, bytes32 tokenId1, bytes32 tokenId2, uint256 supplyLimit) public {
        vm.assume(
            ((uint256(tokenId0) >> 4) != (uint256(tokenId1) >> 4))
                && ((uint256(tokenId0) >> 4) != (uint256(tokenId2) >> 4))
                && ((uint256(tokenId1) >> 4) != (uint256(tokenId2) >> 4))
        );
        vm.assume(supplyLimit >= 3 && supplyLimit <= asset.tokenSupplyCap());

        bytes32[] memory tokenIds = new bytes32[](3);
        tokenIds[0] = tokenId0;
        tokenIds[1] = tokenId1;
        tokenIds[2] = tokenId2;

        (UniversalProfile profile,) = deployProfile();

        vm.startPrank(owner);
        asset.setPrice(1 ether);
        asset.setTokenSupplyLimit(supplyLimit);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(address(asset));
        emit TokensReserved(address(profile), tokenIds);
        asset.reserve(address(profile), tokenIds);

        assertEq(tokenIds.length, asset.totalSupply());
        assertEq(tokenIds.length, asset.balanceOf(address(profile)));
        assertEq(address(profile), asset.tokenOwnerOf(tokenId0));
        assertEq(address(profile), asset.tokenOwnerOf(tokenId1));
        assertEq(address(profile), asset.tokenOwnerOf(tokenId2));
    }
}
