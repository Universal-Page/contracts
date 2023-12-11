// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {GenesisDigitalAsset} from "../../../src/assets/lsp7/GenesisDigitalAsset.sol";

contract GenesisDigitalAssetTest is Test {
    GenesisDigitalAsset asset;
    address owner;
    address beneficiary;

    function setUp() public {
        owner = vm.addr(1);
        beneficiary = vm.addr(2);
        asset = new GenesisDigitalAsset("Universal Page Genesis", "UPG", owner, beneficiary);
    }

    function testFuzz_Reserve(uint256 amount) public {
        assertEq(0, asset.balanceOf(beneficiary));
        vm.prank(owner);
        asset.reserve(amount);
        assertEq(amount, asset.balanceOf(beneficiary));
    }

    function testFuzz_Release(uint256 reserved, uint256 released) public {
        vm.assume(reserved >= released);
        vm.prank(owner);
        asset.reserve(reserved);
        assertEq(reserved, asset.balanceOf(beneficiary));

        vm.prank(beneficiary);
        asset.release(released);
        assertEq(reserved - released, asset.balanceOf(beneficiary));
    }
}
