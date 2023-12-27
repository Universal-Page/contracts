// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Vault} from "../../src/pool/Vault.sol";
import {IDepositContract} from "../../src/pool/IDepositContract.sol";

contract VaultTest is Test {
    event Deposited(address indexed account, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed account, address indexed beneficiary, uint256 amount);
    event WithdrawalRequested(address indexed account, address indexed beneficiary, uint256 amount);
    event Claimed(address indexed account, address indexed beneficiary, uint256 amount);
    event DepositLimitChanged(uint256 previousLimit, uint256 newLimit);
    event FeeChanged(uint32 previousFee, uint32 newFee);
    event FeeRecipientChanged(address previousFeeRecipient, address newFeeRecipient);
    event FeeClaimed(address indexed account, address indexed beneficiary, uint256 amount);
    event FeeReceived(uint256 amount);

    Vault vault;
    address admin;
    address owner;
    address oracle;
    address beneficiary;
    address feeRecipient;
    MockDepositContract depositContract;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);
        oracle = vm.addr(3);
        beneficiary = vm.addr(4);
        feeRecipient = vm.addr(5);

        depositContract = new MockDepositContract();

        vault = Vault(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new Vault()),
                        admin,
                        abi.encodeWithSelector(
                            Vault.initialize.selector,
                            owner,
                            depositContract
                        )
                    )
                )
            )
        );
    }

    function test_Initialize() public {
        assertTrue(!vault.paused());
        assertEq(owner, vault.owner());
        assertEq(0, vault.depositLimit());
        assertEq(0, vault.totalShares());
        assertEq(0, vault.totalAmount());
        assertEq(0, vault.availableAmount());
        assertEq(0, vault.pendingWithdrawalAmount());
        assertEq(0, vault.validators());
        assertEq(0, vault.fee());
        assertEq(address(0), vault.feeRecipient());
        assertEq(0, vault.claimableFeeAmount());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        vault.pause();
        vault.unpause();
        vault.setDepositLimit(2 * 32 ether);
        vault.enableOracle(oracle, true);
        vault.enableOracle(oracle, false);
        vault.setFee(1);
        vault.setFeeRecipient(feeRecipient);
        vault.setRestricted(true);
        vault.allowlist(address(0), true);
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.setDepositLimit(2 * 32 ether);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.enableOracle(oracle, true);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.unpause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.setFee(1);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.setFeeRecipient(feeRecipient);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.setRestricted(true);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.allowlist(address(0), true);
    }

    function test_Revert_IfCallerNotOracle() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOracle.selector, address(1)));
        vault.rebalance();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOracle.selector, address(1)));
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));
    }

    function test_Revert_DepositZero() public {
        vm.prank(vm.addr(100));
        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidAmount.selector, 0));
        vault.deposit{value: 0}(beneficiary);
    }

    function test_Revert_DepositOverLimit() public {
        vm.prank(owner);
        vault.setDepositLimit(10 ether);

        address alice = vm.addr(100);
        vm.deal(alice, 11 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.DepositLimitExceeded.selector, 11 ether, 10 ether));
        vault.deposit{value: 11 ether}(beneficiary);
    }

    function test_DepositPartialValidator(uint256 amount) public {
        vm.assume(amount > 0 && amount < 32 ether);

        vm.prank(owner);
        vault.setDepositLimit(32 ether);

        address alice = vm.addr(100);
        vm.deal(alice, amount);

        vm.prank(alice);
        vm.expectEmit();
        emit Deposited(alice, beneficiary, amount);
        vault.deposit{value: amount}(beneficiary);

        assertEq(amount, vault.totalAmount());
        assertEq(amount, vault.availableAmount());
        assertEq(amount, vault.totalShares());
        assertEq(amount, vault.sharesOf(beneficiary));
        assertEq(0, vault.validators());
    }

    function test_DepositMultipleValidators(uint256 amount, uint256 depositLimit) public {
        vm.assume(amount >= 32 ether);
        vm.assume(depositLimit >= amount);

        vm.prank(owner);
        vault.setDepositLimit(depositLimit);

        address alice = vm.addr(100);
        vm.deal(alice, amount);

        vm.prank(alice);
        vm.expectEmit();
        emit Deposited(alice, beneficiary, amount);
        vault.deposit{value: amount}(beneficiary);

        assertEq(amount, vault.totalAmount());
        assertEq(amount, vault.availableAmount());
        assertEq(amount, vault.totalShares());
        assertEq(amount, vault.sharesOf(beneficiary));
        assertEq(0, vault.validators());
    }

    function test_DepositEnoughAndRegisterSingleValidator() public {
        uint256 amount = 35 ether;

        vm.prank(owner);
        vault.setDepositLimit(amount);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, amount);

        vm.prank(alice);
        vault.deposit{value: amount}(beneficiary);

        assertEq(amount, vault.totalAmount());
        assertEq(amount, vault.availableAmount());
        assertEq(amount, vault.totalShares());
        assertEq(amount, vault.sharesOf(beneficiary));
        assertEq(0, vault.validators());
        assertEq(amount, address(vault).balance);

        assertEq(0, address(depositContract).balance);
        assertEq(0, depositContract.depositCount());

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(amount, vault.totalAmount());
        assertEq(3 ether, vault.availableAmount());
        assertEq(amount, vault.totalShares());
        assertEq(amount, vault.sharesOf(beneficiary));
        assertEq(1, vault.validators());
        assertEq(3 ether, address(vault).balance);

        assertEq(32 ether, address(depositContract).balance);
        assertEq(1, depositContract.depositCount());
    }

    function test_Revert_RegisterSameValidator() public {
        uint256 amount = 64 ether;

        vm.prank(owner);
        vault.setDepositLimit(amount);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, amount);

        vm.prank(alice);
        vault.deposit{value: amount}(beneficiary);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(Vault.ValidatorAlreadyRegistered.selector, hex"1234"));
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));
    }

    function test_DepositMultipleTimesAndRegisterSingleValidator() public {
        vm.prank(owner);
        vault.setDepositLimit(100 ether);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        address bob = vm.addr(101);

        vm.deal(alice, 20 ether);
        vm.deal(bob, 30 ether);

        vm.prank(alice);
        vault.deposit{value: 20 ether}(alice);

        assertEq(20 ether, vault.totalAmount());
        assertEq(20 ether, vault.availableAmount());
        assertEq(20 ether, vault.totalShares());
        assertEq(20 ether, vault.sharesOf(alice));
        assertEq(0 ether, vault.sharesOf(bob));
        assertEq(0, vault.validators());
        assertEq(20 ether, address(vault).balance);

        vm.prank(bob);
        vault.deposit{value: 30 ether}(bob);

        assertEq(50 ether, vault.totalAmount());
        assertEq(50 ether, vault.availableAmount());
        assertEq(50 ether, vault.totalShares());
        assertEq(20 ether, vault.sharesOf(alice));
        assertEq(30 ether, vault.sharesOf(bob));
        assertEq(0, vault.validators());
        assertEq(50 ether, address(vault).balance);

        assertEq(0, address(depositContract).balance);
        assertEq(0, depositContract.depositCount());

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(50 ether, vault.totalAmount());
        assertEq(18 ether, vault.availableAmount());
        assertEq(50 ether, vault.totalShares());
        assertEq(20 ether, vault.sharesOf(alice));
        assertEq(30 ether, vault.sharesOf(bob));
        assertEq(1, vault.validators());
        assertEq(18 ether, address(vault).balance);

        assertEq(32 ether, address(depositContract).balance);
        assertEq(1, depositContract.depositCount());
    }

    function test_DepositAndWithdraw() public {
        vm.prank(owner);
        vault.setDepositLimit(100 ether);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, 40 ether);

        vm.prank(alice);
        vault.deposit{value: 40 ether}(alice);

        assertEq(40 ether, vault.totalAmount());
        assertEq(40 ether, vault.availableAmount());
        assertEq(40 ether, vault.totalShares());
        assertEq(40 ether, vault.sharesOf(alice));
        assertEq(0, vault.validators());
        assertEq(40 ether, address(vault).balance);

        vm.prank(alice);
        vm.expectEmit();
        emit Withdrawn(alice, alice, 5 ether);
        vault.withdraw(5 ether, alice);

        assertEq(35 ether, vault.totalAmount());
        assertEq(35 ether, vault.availableAmount());
        assertEq(35 ether, vault.totalShares());
        assertEq(35 ether, vault.sharesOf(alice));
        assertEq(0, vault.validators());
        assertEq(35 ether, address(vault).balance);
        assertEq(5 ether, alice.balance);
    }

    function test_Revert_WithdrawalExceedsDeposits() public {
        vm.prank(owner);
        vault.setDepositLimit(100 ether);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, 40 ether);

        vm.prank(alice);
        vault.deposit{value: 40 ether}(alice);

        assertEq(40 ether, vault.totalAmount());
        assertEq(40 ether, vault.availableAmount());
        assertEq(40 ether, vault.totalShares());
        assertEq(40 ether, vault.sharesOf(alice));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 40 ether, 41 ether));
        vault.withdraw(41 ether, alice);
    }

    function test_WithdrawAndExitValidator() public {
        vm.prank(owner);
        vault.setDepositLimit(100 ether);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, 33 ether);

        vm.prank(alice);
        vault.deposit{value: 33 ether}(alice);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(33 ether, vault.totalAmount());
        assertEq(1 ether, vault.availableAmount());
        assertEq(33 ether, vault.totalShares());
        assertEq(33 ether, vault.sharesOf(alice));
        assertEq(0, vault.pendingWithdrawalAmount());
        assertEq(0, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));
        assertEq(1, vault.validators());
        assertEq(1 ether, address(vault).balance);

        assertEq(32 ether, address(depositContract).balance);
        assertEq(1, depositContract.depositCount());

        vm.prank(alice);
        vm.expectEmit();
        emit Withdrawn(alice, alice, 1 ether);
        vm.expectEmit();
        emit WithdrawalRequested(alice, alice, 2 ether);
        vault.withdraw(3 ether, alice);

        assertEq(30 ether, vault.totalAmount());
        assertEq(0, vault.availableAmount());
        assertEq(30 ether, vault.totalShares());
        assertEq(30 ether, vault.sharesOf(alice));
        assertEq(2 ether, vault.pendingWithdrawalAmount());
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));
        assertEq(1, vault.validators());
        assertEq(0, address(vault).balance);

        // simulate widthdrawal from deposit contract
        vm.deal(address(vault), 32 ether);

        assertEq(2 ether, vault.pendingWithdrawalAmount());
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(2 ether, vault.claimableBalanceOf(alice));
    }

    function test_WithdrawAndClaimMultipleLater() public {
        vm.prank(owner);
        vault.setDepositLimit(100 ether);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, 33 ether);

        vm.prank(alice);
        vault.deposit{value: 33 ether}(alice);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        vm.prank(alice);
        vault.withdraw(3 ether, alice);

        assertEq(2 ether, vault.pendingWithdrawalAmount());
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));

        // simulate widthdrawal from deposit contract
        vm.deal(address(vault), 32 ether);

        vm.prank(alice);
        vm.expectEmit();
        emit Claimed(alice, alice, 1.5 ether);
        vault.claim(1.5 ether, alice);

        assertEq(0.5 ether, vault.pendingWithdrawalAmount());
        assertEq(0.5 ether, vault.pendingBalanceOf(alice));
        assertEq(0.5 ether, vault.claimableBalanceOf(alice));

        vm.prank(alice);
        vm.expectEmit();
        emit Claimed(alice, alice, 0.5 ether);
        vault.claim(0.5 ether, alice);

        assertEq(0, vault.pendingWithdrawalAmount());
        assertEq(0, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));
    }

    function test_DistributeRewardsAndFees() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 33 ether);
        vm.prank(alice);
        vault.deposit{value: 33 ether}(alice);

        address bob = vm.addr(101);
        vm.deal(bob, 46 ether);
        vm.prank(bob);
        vault.deposit{value: 46 ether}(bob);

        assertEq(79 ether, vault.totalAmount());
        assertEq(79 ether, vault.availableAmount());
        assertEq(79 ether, vault.totalShares());
        assertEq(33 ether, vault.sharesOf(alice));
        assertEq(46 ether, vault.sharesOf(bob));
        assertEq(0, vault.validators());
        assertEq(79 ether, address(vault).balance);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        vm.prank(oracle);
        vault.registerValidator(hex"4321", hex"8765", bytes32(0));

        assertEq(79 ether, vault.totalAmount());
        assertEq(15 ether, vault.availableAmount());
        assertEq(79 ether, vault.totalShares());
        assertEq(33 ether, vault.sharesOf(alice));
        assertEq(33 ether, vault.balanceOf(alice));
        assertEq(46 ether, vault.sharesOf(bob));
        assertEq(46 ether, vault.balanceOf(bob));
        assertEq(0, vault.claimableFeeAmount());
        assertEq(2, vault.validators());
        assertEq(15 ether, address(vault).balance);

        // simulate rewards + 11 ether
        vm.deal(address(vault), 26 ether);

        vm.prank(oracle);
        vm.expectEmit();
        emit FeeReceived(1.1 ether);
        vault.rebalance();

        assertEq(88.9 ether, vault.totalAmount());
        assertEq(24.9 ether, vault.availableAmount());
        assertEq(79 ether, vault.totalShares());
        assertEq(33 ether, vault.sharesOf(alice));
        assertEq(33 ether + Math.mulDiv(33 ether, 88.9 ether - 79 ether, 79 ether), vault.balanceOf(alice));
        assertEq(46 ether, vault.sharesOf(bob));
        assertEq(46 ether + Math.mulDiv(46 ether, 88.9 ether - 79 ether, 79 ether), vault.balanceOf(bob));
        assertEq(1.1 ether, vault.claimableFeeAmount());
        assertEq(2, vault.validators());
        assertEq(26 ether, address(vault).balance);

        vm.prank(feeRecipient);
        vm.expectEmit();
        emit FeeClaimed(feeRecipient, feeRecipient, 1 ether);
        vault.claimFees(1 ether, feeRecipient);

        assertEq(0.1 ether, vault.claimableFeeAmount());
        assertEq(25 ether, address(vault).balance);
        assertEq(1 ether, feeRecipient.balance);

        vm.prank(feeRecipient);
        vm.expectEmit();
        emit FeeClaimed(feeRecipient, feeRecipient, 0.1 ether);
        vault.claimFees(0.1 ether, feeRecipient);

        assertEq(0, vault.claimableFeeAmount());
        assertEq(24.9 ether, address(vault).balance);
        assertEq(1.1 ether, feeRecipient.balance);
    }

    function test_DepositAfterRewards() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}(alice);

        address bob = vm.addr(101);
        vm.deal(bob, 16 ether);
        vm.prank(bob);
        vault.deposit{value: 16 ether}(bob);

        assertEq(26 ether, vault.totalAmount());
        assertEq(26 ether, vault.availableAmount());
        assertEq(26 ether, vault.totalShares());
        assertEq(10 ether, vault.sharesOf(alice));
        assertEq(10 ether, vault.balanceOf(alice));
        assertEq(16 ether, vault.sharesOf(bob));
        assertEq(16 ether, vault.balanceOf(bob));
        assertEq(26 ether, address(vault).balance);

        // 50% rewards
        vm.deal(address(vault), 39 ether);

        vm.prank(oracle);
        vault.rebalance();

        assertEq(39 ether, vault.totalAmount());
        assertEq(39 ether, vault.availableAmount());
        assertEq(26 ether, vault.totalShares());
        assertEq(10 ether, vault.sharesOf(alice));
        assertEq(15 ether, vault.balanceOf(alice));
        assertEq(16 ether, vault.sharesOf(bob));
        assertEq(24 ether, vault.balanceOf(bob));
        assertEq(39 ether, address(vault).balance);

        vm.deal(bob, 15 ether);
        vm.prank(bob);
        vault.deposit{value: 15 ether}(bob);

        assertEq(54 ether, vault.totalAmount());
        assertEq(54 ether, vault.availableAmount());
        assertEq(36 ether, vault.totalShares());
        assertEq(10 ether, vault.sharesOf(alice));
        assertEq(15 ether, vault.balanceOf(alice));
        assertEq(26 ether, vault.sharesOf(bob));
        assertEq(39 ether, vault.balanceOf(bob));
        assertEq(54 ether, address(vault).balance);
    }

    function test_WithdrawAfterRewards() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vault.deposit{value: 10 ether}(alice);

        address bob = vm.addr(101);
        vm.deal(bob, 16 ether);
        vm.prank(bob);
        vault.deposit{value: 16 ether}(bob);

        // 50% rewards
        vm.deal(address(vault), 39 ether);

        vm.prank(oracle);
        vault.rebalance();

        vm.deal(bob, 15 ether);
        vm.prank(bob);
        vault.deposit{value: 15 ether}(bob);

        assertEq(54 ether, vault.totalAmount());
        assertEq(54 ether, vault.availableAmount());
        assertEq(36 ether, vault.totalShares());
        assertEq(10 ether, vault.sharesOf(alice));
        assertEq(15 ether, vault.balanceOf(alice));
        assertEq(26 ether, vault.sharesOf(bob));
        assertEq(39 ether, vault.balanceOf(bob));
        assertEq(54 ether, address(vault).balance);
        assertEq(0 ether, bob.balance);

        vm.prank(bob);
        vault.withdraw(9 ether, bob);

        assertEq(45 ether, vault.totalAmount());
        assertEq(45 ether, vault.availableAmount());
        assertEq(30 ether, vault.totalShares());
        assertEq(10 ether, vault.sharesOf(alice));
        assertEq(15 ether, vault.balanceOf(alice));
        assertEq(20 ether, vault.sharesOf(bob));
        assertEq(30 ether, vault.balanceOf(bob));
        assertEq(45 ether, address(vault).balance);
        assertEq(9 ether, bob.balance);
    }
}

contract MockDepositContract is IDepositContract {
    bytes32 public depositRoot;
    uint256 public depositCount;

    function deposit(bytes calldata, bytes calldata, bytes calldata, bytes32) external payable override {
        depositCount++;
    }

    function get_deposit_root() external view override returns (bytes32) {
        return depositRoot;
    }

    function get_deposit_count() external view override returns (bytes memory) {
        return abi.encodePacked(depositCount);
    }
}
