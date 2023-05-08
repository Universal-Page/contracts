// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY,
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_TOKEN_TYPE_NFT
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {
    _LSP8_TOKENID_FORMAT_KEY,
    _LSP8_TOKENID_FORMAT_STRING
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {UniversalProfile} from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {PageName} from "../../src/page/PageName.sol";
import {deployProfile} from "../utils/profile.sol";

contract PageNameTest is Test {
    event ValueReceived(address indexed sender, uint256 indexed value);
    event ValueWithdrawn(address indexed sender, uint256 indexed value);

    event ReservedName(address indexed account, bytes32 indexed tokenId, uint256 price);
    event ReleasedName(address indexed account, bytes32 indexed tokenId);

    PageName name;
    address admin;
    address owner;
    address beneficiary;
    address controller;
    uint256 controllerKey;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);
        beneficiary = vm.addr(3);

        controllerKey = 4;
        controller = vm.addr(controllerKey);

        name = PageName(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new PageName()),
                        admin,
                        abi.encodeWithSelector(
                            PageName.initialize.selector,
                            "Universal Page Name",
                            "UPN",
                            owner,
                            beneficiary,
                            controller,
                            3
                        )
                    )
                )
            )
        );
    }

    function test_Initialize() public {
        assertTrue(!name.paused());
        assertEq("Universal Page Name", name.getData(_LSP4_TOKEN_NAME_KEY));
        assertEq("UPN", name.getData(_LSP4_TOKEN_SYMBOL_KEY));
        assertEq(_LSP4_TOKEN_TYPE_NFT, uint256(bytes32(name.getData(_LSP4_TOKEN_TYPE_KEY))));
        assertEq(_LSP8_TOKENID_FORMAT_STRING, uint256(bytes32(name.getData(_LSP8_TOKENID_FORMAT_KEY))));
        assertEq(owner, name.owner());
        assertEq(beneficiary, name.beneficiary());
        assertEq(controller, name.controller());
        assertEq(3, name.minimumLength());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        name.setMinimumLength(4);
        name.setController(address(10));
        name.pause();
        name.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.setMinimumLength(4);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.setController(address(100));

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.unpause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.withdraw(0 ether);
    }

    function test_Revert_WhenPaused() public {
        vm.prank(owner);
        name.pause();
        vm.expectRevert("Pausable: paused");
        name.reserve(address(100), "test", false, abi.encode(uint256(0)), 0, 0, 0);
        vm.expectRevert("Pausable: paused");
        name.release(bytes32(uint256(1)));
    }

    function testFuzz_ReceiveMoney(uint256 fund, uint256 deposit) public {
        vm.assume(fund >= deposit);
        vm.assume(deposit > 0);

        assertEq(0 ether, address(name).balance);
        address account = vm.addr(100);
        vm.deal(account, fund);
        vm.prank(account);
        vm.expectEmit(address(name));
        emit ValueReceived(account, deposit);
        (bool success,) = address(name).call{value: deposit}("");
        assertTrue(success);
        assertEq(deposit, address(name).balance);
        assertEq(fund - deposit, account.balance);
    }

    function testFuzz_WithdrawMoney(uint256 fund, uint256 deposit, uint256 withdraw) public {
        vm.assume(fund >= deposit);
        vm.assume(deposit >= withdraw);

        address alice = vm.addr(100);
        vm.deal(alice, fund);
        vm.prank(alice);
        (bool success,) = address(name).call{value: deposit}("");
        assertTrue(success);
        assertEq(deposit, address(name).balance);
        assertEq(0 ether, beneficiary.balance);

        vm.prank(owner);
        vm.expectEmit(address(name));
        emit ValueWithdrawn(beneficiary, withdraw);
        name.withdraw(withdraw);
        assertEq(deposit - withdraw, address(name).balance);
        assertEq(withdraw, beneficiary.balance);
    }

    function testFuzz_Reserve(uint8 minimumLength) public {
        vm.assume(minimumLength <= 32);

        vm.prank(owner);
        name.setMinimumLength(minimumLength);

        bytes memory buffer = new bytes(minimumLength);
        for (uint256 i = 0; i < minimumLength; i++) {
            buffer[i] = bytes1(uint8(0x61 + uint256(blockhash(block.number + i)) % (0x7a - 0x61)));
        }
        string memory reservationName = string(buffer);

        (UniversalProfile profile,) = deployProfile();
        bytes memory salt = abi.encode(uint256(0));

        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name), block.chainid, address(profile), reservationName, false, salt, uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectEmit(address(name));
        emit ReservedName(address(profile), bytes32(bytes(reservationName)), 0 ether);
        name.reserve(address(profile), reservationName, false, salt, v, r, s);
        assertEq(1, name.balanceOf(address(profile)));
    }

    function test_Revert_ReserveIfUnathorized() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name), block.chainid, address(profile), "test", false, abi.encode(uint256(0)), uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(100, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.UnauthorizedReservation.selector, address(profile), "test", 0 ether)
        );
        name.reserve(address(profile), "test", false, abi.encode(uint256(0)), v, r, s);
    }

    function testFuzz_Revert_ReserveIfShortName(uint8 minimumLength, string calldata reservationName) public {
        vm.assume(bytes(reservationName).length < minimumLength);

        vm.prank(owner);
        name.setMinimumLength(minimumLength);

        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name),
                block.chainid,
                address(profile),
                reservationName,
                false,
                abi.encode(uint256(0)),
                uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.IncorrectReservationName.selector, address(profile), reservationName)
        );
        name.reserve(address(profile), reservationName, false, abi.encode(uint256(0)), v, r, s);
    }

    function testFuzz_Revert_ReserveIfLongName(uint8 minimumLength, string calldata reservationName) public {
        vm.assume(bytes(reservationName).length > 32);

        vm.prank(owner);
        name.setMinimumLength(minimumLength);

        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name),
                block.chainid,
                address(profile),
                reservationName,
                false,
                abi.encode(uint256(0)),
                uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.IncorrectReservationName.selector, address(profile), reservationName)
        );
        name.reserve(address(profile), reservationName, false, abi.encode(uint256(0)), v, r, s);
    }

    function testFuzz_Revert_ReserveIfContainsInvalidCharacters(bytes1 char) public {
        vm.assume(
            ((char >= 0 && char < 0x30) || (char > 0x39 && char < 0x61) || char > 0x7a) && char != 0x2d && char != 0x5f
        ); // not a-z0-9-_

        string memory reservationName = string(abi.encodePacked("test", char));

        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name),
                block.chainid,
                address(profile),
                reservationName,
                false,
                abi.encode(uint256(0)),
                uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.IncorrectReservationName.selector, address(profile), reservationName)
        );
        name.reserve(address(profile), reservationName, false, abi.encode(uint256(0)), v, r, s);
    }

    function test_Revert_ReserveMultiple() public {
        (UniversalProfile profile,) = deployProfile();
        {
            bytes32 hash = keccak256(
                abi.encodePacked(
                    address(name),
                    block.chainid,
                    address(profile),
                    "test1",
                    false,
                    abi.encode(uint256(0)),
                    uint256(0 ether)
                )
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            vm.expectEmit(address(name));
            emit ReservedName(address(profile), bytes32(bytes("test1")), 0 ether);
            name.reserve(address(profile), "test1", false, abi.encode(uint256(0)), v, r, s);
            assertEq(1, name.balanceOf(address(profile)));
        }
        {
            bytes32 hash = keccak256(
                abi.encodePacked(
                    address(name),
                    block.chainid,
                    address(profile),
                    "test2",
                    false,
                    abi.encode(uint256(1)),
                    uint256(0 ether)
                )
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            vm.expectRevert(
                abi.encodeWithSelector(PageName.UnauthorizedReservation.selector, address(profile), "test2", 0 ether)
            );
            name.reserve(address(profile), "test2", false, abi.encode(uint256(1)), v, r, s);
            assertEq(1, name.balanceOf(address(profile)));
        }
    }

    function test_Release() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name), block.chainid, address(profile), "test", false, abi.encode(uint256(0)), uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        name.reserve(address(profile), "test", false, abi.encode(uint256(0)), v, r, s);
        assertEq(1, name.totalSupply());
        assertEq(1, name.balanceOf(address(profile)));

        vm.prank(address(profile));
        vm.expectEmit(address(name));
        emit ReleasedName(address(profile), bytes32("test"));
        name.release(bytes32("test"));
        assertEq(0, name.totalSupply());
        assertEq(0, name.balanceOf(address(profile)));
    }

    function test_Revert_ReleaseIfUnathorized() public {
        (UniversalProfile alice,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name), block.chainid, address(alice), "test", false, abi.encode(uint256(0)), uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(alice));
        name.reserve(address(alice), "test", false, abi.encode(uint256(0)), v, r, s);
        (UniversalProfile bob,) = deployProfile();

        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(PageName.UnauthorizedRelease.selector, address(bob), bytes32("test")));
        name.release(bytes32("test"));
    }

    function test_Revert_ReserveWhenReleasedAndUseSameSignature() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(name), block.chainid, address(profile), "test", false, abi.encode(uint256(0)), uint256(0 ether)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        {
            vm.prank(address(profile));
            name.reserve(address(profile), "test", false, abi.encode(uint256(0)), v, r, s);
        }
        {
            vm.prank(address(profile));
            name.release(bytes32("test"));
        }
        {
            vm.prank(address(profile));
            vm.expectRevert(
                abi.encodeWithSelector(PageName.UnauthorizedReservation.selector, address(profile), "test", 0 ether)
            );
            name.reserve(address(profile), "test", false, abi.encode(uint256(0)), v, r, s);
        }
    }
}
