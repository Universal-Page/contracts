// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ProfilesReverseLookup} from "../../src/profiles/ProfilesReverseLookup.sol";

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");

        vm.broadcast(admin);
        ProfilesReverseLookup lookup = new ProfilesReverseLookup();
        console.log(string.concat("ProfilesReverseLookup: deploy ", Strings.toHexString(address(lookup))));
    }
}
