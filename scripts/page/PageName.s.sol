// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {LSP6KeyManager} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManager.sol";
import {OPERATION_0_CALL} from "@erc725/smart-contracts/contracts/constants.sol";
import {PageName} from "../../src/page/PageName.sol";

uint16 constant PROFILE_LIMIT = 1;
uint8 constant MINIMUM_LENGTH = 3;
uint256 constant PRICE = 1 ether;

contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address profile = vm.envAddress("PROFILE_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address controller = vm.envAddress("PAGE_NAME_CONTROLLER_ADDRESS");
        address marketplace = vm.envAddress("CONTRACT_LSP8_MARKETPLACE_ADDRESS");

        address proxy = vm.envOr("CONTRACT_PAGE_NAME_ADDRESS", address(0));

        vm.broadcast(admin);
        PageName pageName = new PageName();

        if (proxy == address(0)) {
            vm.broadcast(admin);
            proxy = address(
                new TransparentUpgradeableProxy(
                    address(pageName),
                    admin,
                    abi.encodeWithSelector(
                      PageName.initialize.selector,
                      "Universal Page Name",
                      "UPN",
                      profile,
                      treasury,
                      controller,
                      PRICE,
                      MINIMUM_LENGTH,
                      PROFILE_LIMIT,
                      marketplace)
                )
            );
            console.log(string.concat("PageName: deploy ", Strings.toHexString(address(proxy))));
        } else {
            vm.broadcast(admin);
            ITransparentUpgradeableProxy(proxy).upgradeTo(address(pageName));
            console.log(string.concat("PageName: upgrade ", Strings.toHexString(address(proxy))));
        }
    }
}

contract Configure is Script {
    bytes32 private constant _LSP8_TOKEN_METADATA_BASE_URI_KEY =
        0x1a7628600c3bac7101f53697f48df381ddc36b9015e7d7c9c5633d1252aa2843;

    bytes4 private constant _baseUriHash = bytes4(bytes32(keccak256("keccak256(utf8)")));

    function run() external {
        address controller = vm.envAddress("PROFILE_CONTROLLER_ADDRESS");
        UniversalProfile profile = UniversalProfile(payable(vm.envAddress("PROFILE_ADDRESS")));
        LSP6KeyManager keyManager = LSP6KeyManager(profile.owner());
        PageName pageName = PageName(payable(vm.envAddress("CONTRACT_PAGE_NAME_ADDRESS")));

        bytes memory currentBaseUri = pageName.getData(_LSP8_TOKEN_METADATA_BASE_URI_KEY);
        string memory baseUri = vm.envString("PAGE_NAME_BASE_URI");
        bytes memory encodedBaseUri = bytes.concat(_baseUriHash, bytes(baseUri));
        if (keccak256(encodedBaseUri) != keccak256(currentBaseUri)) {
            vm.broadcast(controller);
            keyManager.execute(
                abi.encodeWithSelector(
                    profile.execute.selector,
                    OPERATION_0_CALL,
                    address(pageName),
                    0,
                    abi.encodeWithSelector(pageName.setData.selector, _LSP8_TOKEN_METADATA_BASE_URI_KEY, encodedBaseUri)
                )
            );
        }

        if (pageName.price() != PRICE) {
            vm.broadcast(controller);
            keyManager.execute(
                abi.encodeWithSelector(
                    profile.execute.selector,
                    OPERATION_0_CALL,
                    address(pageName),
                    0,
                    abi.encodeWithSelector(pageName.setPrice.selector, PRICE)
                )
            );
        }

        if (pageName.profileLimit() != PROFILE_LIMIT) {
            vm.broadcast(controller);
            keyManager.execute(
                abi.encodeWithSelector(
                    profile.execute.selector,
                    OPERATION_0_CALL,
                    address(pageName),
                    0,
                    abi.encodeWithSelector(pageName.setProfileLimit.selector, PROFILE_LIMIT)
                )
            );
        }

        if (pageName.minimumLength() != MINIMUM_LENGTH) {
            vm.broadcast(controller);
            keyManager.execute(
                abi.encodeWithSelector(
                    profile.execute.selector,
                    OPERATION_0_CALL,
                    address(pageName),
                    0,
                    abi.encodeWithSelector(pageName.setMinimumLength.selector, MINIMUM_LENGTH)
                )
            );
        }
    }
}
