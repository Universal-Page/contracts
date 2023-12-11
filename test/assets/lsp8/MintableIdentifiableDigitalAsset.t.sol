// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {MintableIdentifiableDigitalAsset} from "../../../src/assets/lsp8/MintableIdentifiableDigitalAsset.sol";

contract MintableIdentifiableDigitalAssetTest is Test {
    address owner;

    function setUp() public {
        owner = vm.addr(1);
    }

    function test() public {
        MintableIdentifiableDigitalAsset asset = new MintableIdentifiableDigitalAsset("Test", "TST", owner, 1, 1, 100);
        assertEq(0, asset.totalSupply());
        assertEq(100, asset.tokenSupplyCap());
        assertEq(owner, asset.owner());
    }
}
