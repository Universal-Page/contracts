// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {
    _LSP4_TOKEN_TYPE_TOKEN,
    _LSP4_TOKEN_TYPE_NFT
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {MintableDigitalAsset} from "../../../src/assets/lsp7/MintableDigitalAsset.sol";

contract MintableDigitalAssetTest is Test {
    address owner;

    function setUp() public {
        owner = vm.addr(1);
    }

    function test_NonDivisble() public {
        MintableDigitalAsset asset = new MintableDigitalAsset("Test", "TST", owner, _LSP4_TOKEN_TYPE_NFT, true, 100);
        assertEq(0, asset.totalSupply());
        assertEq(100, asset.tokenSupplyCap());
        assertEq(owner, asset.owner());
        assertEq(0, asset.decimals());
    }

    function test_Divisible() public {
        MintableDigitalAsset asset = new MintableDigitalAsset("Test", "TST", owner, _LSP4_TOKEN_TYPE_TOKEN, false, 100);
        assertEq(0, asset.totalSupply());
        assertEq(100, asset.tokenSupplyCap());
        assertEq(owner, asset.owner());
        assertEq(18, asset.decimals());
    }
}
