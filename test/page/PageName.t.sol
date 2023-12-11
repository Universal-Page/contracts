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
import {IPageNameMarketplace, PendingSale} from "../../src/page/IPageNameMarketplace.sol";
import {PageName} from "../../src/page/PageName.sol";
import {deployProfile} from "../utils/profile.sol";
import {PageNameMarketplaceMock} from "./PageNameMarketplaceMock.sol";

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
    PageNameMarketplaceMock marketplace;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);
        beneficiary = vm.addr(3);

        controllerKey = 4;
        controller = vm.addr(controllerKey);

        marketplace = new PageNameMarketplaceMock();
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
                            1 ether,
                            3,
                            2,
                            marketplace
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
        assertEq(1 ether, name.price());
        assertEq(3, name.minimumLength());
        assertEq(2, name.profileLimit());
        assertEq(address(marketplace), address(name.marketplace()));
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        name.setProfileLimit(10);
        name.setMinimumLength(4);
        name.setPrice(0 ether);
        name.setController(address(10));
        name.pause();
        name.unpause();
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.setProfileLimit(10);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.setMinimumLength(4);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        name.setPrice(0 ether);

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
        name.reserve(address(100), "test", 0, 0, 0);
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
        bytes32 hash = keccak256(
            abi.encodePacked(address(name), block.chainid, address(profile), reservationName, uint256(0 ether))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectEmit(address(name));
        emit ReservedName(address(profile), bytes32(bytes(reservationName)), 0 ether);
        name.reserve(address(profile), reservationName, v, r, s);
        assertEq(1, name.balanceOf(address(profile)));
    }

    function test_Revert_ReserveIfUnathorized() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(abi.encodePacked(address(name), address(profile), "test", uint256(0 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(100, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.UnauthorizedReservation.selector, address(profile), "test", 0 ether)
        );
        name.reserve(address(profile), "test", v, r, s);
    }

    function testFuzz_Revert_ReserveIfShortName(uint8 minimumLength, string calldata reservationName) public {
        vm.assume(bytes(reservationName).length < minimumLength);

        vm.prank(owner);
        name.setMinimumLength(minimumLength);

        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(address(name), block.chainid, address(profile), reservationName, uint256(0 ether))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.IncorrectReservationName.selector, address(profile), reservationName)
        );
        name.reserve(address(profile), reservationName, v, r, s);
    }

    function testFuzz_Revert_ReserveIfLongName(uint8 minimumLength, string calldata reservationName) public {
        vm.assume(bytes(reservationName).length > 32);

        vm.prank(owner);
        name.setMinimumLength(minimumLength);

        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(address(name), block.chainid, address(profile), reservationName, uint256(0 ether))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.IncorrectReservationName.selector, address(profile), reservationName)
        );
        name.reserve(address(profile), reservationName, v, r, s);
    }

    function testFuzz_Revert_ReserveIfContainsInvalidCharacters(bytes1 char) public {
        vm.assume(
            ((char >= 0 && char < 0x30) || (char > 0x39 && char < 0x61) || char > 0x7a) && char != 0x2d && char != 0x5f
        ); // not a-z0-9-_

        string memory reservationName = string(abi.encodePacked("test", char));

        (UniversalProfile profile,) = deployProfile();
        bytes32 hash = keccak256(
            abi.encodePacked(address(name), block.chainid, address(profile), reservationName, uint256(0 ether))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        vm.expectRevert(
            abi.encodeWithSelector(PageName.IncorrectReservationName.selector, address(profile), reservationName)
        );
        name.reserve(address(profile), reservationName, v, r, s);
    }

    function test_Revert_ReserveWhenExceedProfileLimit() public {
        (UniversalProfile profile,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(2);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            name.reserve(address(profile), "test1", v, r, s);
            assertEq(1, name.balanceOf(address(profile)));
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test2", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            name.reserve(address(profile), "test2", v, r, s);
            assertEq(2, name.balanceOf(address(profile)));
        }
    }

    function test_ReserveWhenExceedProfileLimit() public {
        (UniversalProfile profile,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(1);
        vm.prank(owner);
        name.setPrice(1.5 ether);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            name.reserve(address(profile), "test1", v, r, s);
            assertEq(1, name.balanceOf(address(profile)));
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test2", uint256(1.5 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.deal(address(profile), 2 ether);
            vm.prank(address(profile));
            vm.expectEmit(address(name));
            emit ReservedName(address(profile), bytes32("test2"), 1.5 ether);
            name.reserve{value: 1.5 ether}(address(profile), "test2", v, r, s);
            assertEq(2, name.balanceOf(address(profile)));
            assertEq(1.5 ether, address(name).balance);
            assertEq(0.5 ether, address(profile).balance);
        }
    }

    function test_Release() public {
        (UniversalProfile profile,) = deployProfile();
        bytes32 hash =
            keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test", uint256(0 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(profile));
        name.reserve(address(profile), "test", v, r, s);
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
        bytes32 hash =
            keccak256(abi.encodePacked(address(name), block.chainid, address(alice), "test", uint256(0 ether)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        vm.prank(address(alice));
        name.reserve(address(alice), "test", v, r, s);
        (UniversalProfile bob,) = deployProfile();

        vm.prank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(PageName.UnauthorizedRelease.selector, address(bob), bytes32("test")));
        name.release(bytes32("test"));
    }

    function test_ReserveFreeIfPaidRelease() public {
        (UniversalProfile profile,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(1);
        vm.prank(owner);
        name.setPrice(1 ether);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            name.reserve(address(profile), "test1", v, r, s);
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test2", uint256(1 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            vm.deal(address(profile), 1 ether);
            name.reserve{value: 1 ether}(address(profile), "test2", v, r, s);
        }
        {
            vm.prank(address(profile));
            name.release("test2");
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(profile), "test3", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(profile));
            name.reserve(address(profile), "test3", v, r, s);
        }
    }

    function test_ReserveFreeWhenTransferred() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(1);
        vm.prank(owner);
        name.setPrice(1 ether);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(alice), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(alice));
            name.reserve(address(alice), "test1", v, r, s);
            assertEq(1, name.balanceOf(address(alice)));
            assertEq(0, name.balanceOf(address(bob)));
        }
        {
            vm.prank(address(alice));
            name.transfer(address(alice), address(bob), bytes32("test1"), false, "");
            assertEq(0, name.balanceOf(address(alice)));
            assertEq(1, name.balanceOf(address(bob)));
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(alice), "test2", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(alice));
            name.reserve(address(alice), "test2", v, r, s);
            assertEq(1, name.balanceOf(address(alice)));
            assertEq(1, name.balanceOf(address(bob)));
        }
    }

    function test_TransferWhenSold() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(1);
        vm.prank(owner);
        name.setPrice(1.5 ether);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(alice), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(alice));
            name.reserve(address(alice), "test1", v, r, s);
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(bob), "test2", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(bob));
            name.reserve(address(bob), "test2", v, r, s);
        }
        {
            vm.prank(address(alice));
            name.authorizeOperator(address(marketplace), bytes32("test1"), "");
        }
        {
            marketplace.setPendingSale(
                PendingSale({
                    asset: address(name),
                    tokenId: bytes32("test1"),
                    seller: address(alice),
                    buyer: address(bob),
                    totalPaid: 1.5 ether
                })
            );
            vm.prank(address(marketplace));
            name.transfer(address(alice), address(bob), bytes32("test1"), false, "");
            assertEq(0, name.balanceOf(address(alice)));
            assertEq(2, name.balanceOf(address(bob)));
        }
    }

    function test_Revert_TransferIfSoldLow(uint256 price, uint256 totalPaid) public {
        vm.assume(price > 0.1 ether);
        vm.assume(totalPaid < price);

        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(1);
        vm.prank(owner);
        name.setPrice(price);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(alice), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(alice));
            name.reserve(address(alice), "test1", v, r, s);
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(bob), "test2", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(bob));
            name.reserve(address(bob), "test2", v, r, s);
        }
        {
            vm.prank(address(alice));
            name.authorizeOperator(address(marketplace), bytes32("test1"), "");
        }
        {
            marketplace.setPendingSale(
                PendingSale({
                    asset: address(name),
                    tokenId: bytes32("test1"),
                    seller: address(alice),
                    buyer: address(bob),
                    totalPaid: totalPaid
                })
            );
            vm.prank(address(marketplace));
            vm.expectRevert(
                abi.encodeWithSelector(
                    PageName.TransferInvalidSale.selector, address(alice), address(bob), bytes32("test1"), totalPaid
                )
            );
            name.transfer(address(alice), address(bob), bytes32("test1"), false, "");
        }
    }

    function test_Revert_TransferWhenExceedProfileLimit() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(1);
        vm.prank(owner);
        name.setPrice(1.5 ether);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(alice), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(alice));
            name.reserve(address(alice), "test1", v, r, s);
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(bob), "test2", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(bob));
            name.reserve(address(bob), "test2", v, r, s);
        }
        {
            vm.prank(address(alice));
            vm.expectRevert(
                abi.encodeWithSelector(
                    PageName.TransferExceedLimit.selector, address(alice), address(bob), bytes32("test1"), 1
                )
            );
            name.transfer(address(alice), address(bob), bytes32("test1"), false, "");
        }
    }

    function test_ReserveFreeAfterReleasedSold() public {
        (UniversalProfile alice,) = deployProfile();
        (UniversalProfile bob,) = deployProfile();
        vm.prank(owner);
        name.setProfileLimit(1);
        vm.prank(owner);
        name.setPrice(1.5 ether);
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(alice), "test1", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(alice));
            name.reserve(address(alice), "test1", v, r, s);
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(bob), "test2", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(bob));
            name.reserve(address(bob), "test2", v, r, s);
        }
        {
            vm.prank(address(alice));
            name.authorizeOperator(address(marketplace), bytes32("test1"), "");
        }
        {
            marketplace.setPendingSale(
                PendingSale({
                    asset: address(name),
                    tokenId: bytes32("test1"),
                    seller: address(alice),
                    buyer: address(bob),
                    totalPaid: 1.5 ether
                })
            );
            vm.prank(address(marketplace));
            name.transfer(address(alice), address(bob), bytes32("test1"), false, "");
            assertEq(0, name.balanceOf(address(alice)));
            assertEq(2, name.balanceOf(address(bob)));
        }
        {
            vm.prank(address(bob));
            vm.expectEmit(address(name));
            emit ReleasedName(address(bob), bytes32("test1"));
            name.release(bytes32("test1"));
            assertEq(1, name.balanceOf(address(bob)));
        }
        {
            bytes32 hash =
                keccak256(abi.encodePacked(address(name), block.chainid, address(bob), "test3", uint256(0 ether)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
            vm.prank(address(bob));
            name.reserve(address(bob), "test3", v, r, s);
            assertEq(2, name.balanceOf(address(bob)));
        }
    }
}
