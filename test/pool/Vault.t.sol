// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OwnableCallerNotTheOwner} from "@erc725/smart-contracts/contracts/errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";
import {IVault, Vault, IVaultStakeRecipient} from "../../src/pool/Vault.sol";
import {IDepositContract} from "../../src/pool/IDepositContract.sol";

contract VaultTest is Test {
    uint256 private constant _MINIMUM_REQUIRED_SHARES = 1e3;

    event Deposited(address indexed account, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed account, address indexed beneficiary, uint256 amount);
    event WithdrawalRequested(address indexed account, address indexed beneficiary, uint256 amount);
    event Claimed(address indexed account, address indexed beneficiary, uint256 amount);
    event DepositLimitChanged(uint256 previousLimit, uint256 newLimit);
    event FeeChanged(uint32 previousFee, uint32 newFee);
    event FeeRecipientChanged(address previousFeeRecipient, address newFeeRecipient);
    event FeeClaimed(address indexed account, address indexed beneficiary, uint256 amount);
    event RewardsDistributed(uint256 balance, uint256 rewards, uint256 fee);
    event Rebalanced(
        uint256 previousTotalStaked, uint256 previousTotalUnstaked, uint256 totalStaked, uint256 totalUnstaked
    );
    event ValidatorExited(bytes pubkey, uint256 total);
    event StakeTransferred(address indexed from, address indexed to, uint256 amount, bytes data);

    Vault vault;
    address admin;
    address owner;
    address operator;
    address oracle;
    address beneficiary;
    address feeRecipient;
    MockDepositContract depositContract;

    function setUp() public {
        admin = vm.addr(1);
        owner = vm.addr(2);
        operator = vm.addr(3);
        oracle = vm.addr(4);
        beneficiary = vm.addr(5);
        feeRecipient = vm.addr(6);

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
                            operator,
                            depositContract
                        )
                    )
                )
            )
        );
    }

    function test_Initialize() public {
        assertTrue(ERC165Checker.supportsInterface(address(vault), type(IVault).interfaceId));
        assertTrue(!vault.paused());
        assertEq(owner, vault.owner());
        assertEq(0, vault.depositLimit());
        assertEq(0, vault.totalShares());
        assertEq(0, vault.totalStaked());
        assertEq(0, vault.totalUnstaked());
        assertEq(0, vault.totalPendingWithdrawal());
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(0, vault.fee());
        assertEq(address(0), vault.feeRecipient());
        assertEq(0, vault.totalFees());
    }

    function test_ConfigureIfOwner() public {
        vm.startPrank(owner);
        vault.pause();
        vault.unpause();
        vm.stopPrank();
    }

    function test_ConfigureIfOperator() public {
        vm.startPrank(operator);
        vault.setDepositLimit(2 * 32 ether);
        vault.enableOracle(oracle, true);
        vault.enableOracle(oracle, false);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vault.setRestricted(true);
        vault.allowlist(address(0), true);
        vm.stopPrank();
    }

    function test_Revert_IfConfigureNotOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOperator.selector, address(1)));
        vault.setDepositLimit(2 * 32 ether);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOperator.selector, address(1)));
        vault.enableOracle(oracle, true);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.pause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(OwnableCallerNotTheOwner.selector, address(1)));
        vault.unpause();

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOperator.selector, address(1)));
        vault.setFee(1);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOperator.selector, address(1)));
        vault.setFeeRecipient(feeRecipient);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOperator.selector, address(1)));
        vault.setRestricted(true);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Vault.CallerNotOperator.selector, address(1)));
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
        vm.assume(amount > _MINIMUM_REQUIRED_SHARES && amount < 32 ether);

        vm.prank(owner);
        vault.setDepositLimit(32 ether);

        address alice = vm.addr(100);
        vm.deal(alice, amount);

        vm.prank(alice);
        vm.expectEmit();
        emit Deposited(alice, beneficiary, amount);
        vault.deposit{value: amount}(beneficiary);

        assertEq(0, vault.totalStaked());
        assertEq(amount, vault.totalUnstaked());
        assertEq(amount, vault.totalAssets());
        assertEq(amount - vault.balanceOf(address(0)), vault.balanceOf(beneficiary));
        assertEq(0, vault.totalValidatorsRegistered());
    }

    function test_DepositMultipleValidators(uint256 amount) public {
        vm.assume(amount >= 32 ether && amount <= 1_000_000 * 32 ether);

        vm.prank(owner);
        vault.setDepositLimit(amount);

        address alice = vm.addr(100);
        vm.deal(alice, amount);

        vm.prank(alice);
        vm.expectEmit();
        emit Deposited(alice, beneficiary, amount);
        vault.deposit{value: amount}(beneficiary);

        assertEq(0, vault.totalStaked());
        assertEq(amount, vault.totalUnstaked());
        assertEq(amount, vault.totalAssets());
        assertEq(amount - vault.balanceOf(address(0)), vault.balanceOf(beneficiary));
        assertEq(0, vault.totalValidatorsRegistered());
    }

    function test_DepositEnoughAndRegisterSingleValidator() public {
        vm.prank(owner);
        vault.setDepositLimit(35 ether);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, 35 ether);

        vm.prank(alice);
        vault.deposit{value: 35 ether}(beneficiary);

        assertEq(0, vault.totalStaked());
        assertEq(35 ether, vault.totalUnstaked());
        assertEq(35 ether, vault.totalAssets());
        assertEq(35 ether - vault.balanceOf(address(0)), vault.balanceOf(beneficiary));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(35 ether, address(vault).balance);

        assertEq(0, address(depositContract).balance);
        assertEq(0, depositContract.depositCount());

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(32 ether, vault.totalStaked());
        assertEq(3 ether, vault.totalUnstaked());
        assertEq(35 ether, vault.totalAssets());
        assertEq(35 ether - vault.balanceOf(address(0)), vault.balanceOf(beneficiary));
        assertEq(1, vault.totalValidatorsRegistered());
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

        assertEq(0, vault.totalStaked());
        assertEq(20 ether, vault.totalUnstaked());
        assertEq(20 ether, vault.totalAssets());
        assertEq(20 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.balanceOf(bob));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(20 ether, address(vault).balance);

        vm.prank(bob);
        vault.deposit{value: 30 ether}(bob);

        assertEq(0 ether, vault.totalStaked());
        assertEq(50 ether, vault.totalUnstaked());
        assertEq(50 ether, vault.totalAssets());
        assertEq(20 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(30 ether, vault.balanceOf(bob));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(50 ether, address(vault).balance);

        assertEq(0, address(depositContract).balance);
        assertEq(0, depositContract.depositCount());

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(32 ether, vault.totalStaked());
        assertEq(18 ether, vault.totalUnstaked());
        assertEq(50 ether, vault.totalAssets());
        assertEq(20 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(30 ether, vault.balanceOf(bob));
        assertEq(1, vault.totalValidatorsRegistered());
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

        assertEq(0 ether, vault.totalStaked());
        assertEq(40 ether, vault.totalUnstaked());
        assertEq(40 ether, vault.totalAssets());
        assertEq(40 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(40 ether, address(vault).balance);

        vm.prank(alice);
        vm.expectEmit();
        emit Withdrawn(alice, alice, 5 ether);
        vault.withdraw(5 ether, alice);

        assertEq(0 ether, vault.totalStaked());
        assertEq(35 ether, vault.totalUnstaked());
        assertEq(35 ether, vault.totalAssets());
        assertEq(35 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(35 ether, address(vault).balance);
        assertEq(5 ether, alice.balance);
    }

    function test_DepositBySending() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 40 ether);

        vm.prank(alice);
        (bool success,) = address(vault).call{value: 40 ether}("");
        assertTrue(success);

        assertEq(0 ether, vault.totalStaked());
        assertEq(40 ether, vault.totalUnstaked());
        assertEq(40 ether, vault.totalAssets());
        assertEq(40 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(40 ether, address(vault).balance);
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

        assertEq(0 ether, vault.totalStaked());
        assertEq(40 ether, vault.totalUnstaked());
        assertEq(40 ether, vault.totalAssets());
        assertEq(40 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.InsufficientBalance.selector, 40 ether - vault.balanceOf(address(0)), 41 ether)
        );
        vault.withdraw(41 ether, alice);
        vm.stopPrank();
    }

    function test_WithdrawAndExitValidator() public {
        vm.startBroadcast(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopBroadcast();

        address alice = vm.addr(100);
        vm.deal(alice, 33 ether);

        vm.prank(alice);
        vault.deposit{value: 33 ether}(alice);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(32 ether, vault.totalStaked());
        assertEq(1 ether, vault.totalUnstaked());
        assertEq(33 ether, vault.totalAssets());
        assertEq(33 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0, vault.totalPendingWithdrawal());
        assertEq(0, vault.totalClaimable());
        assertEq(0, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(1 ether, address(vault).balance);

        assertEq(32 ether, address(depositContract).balance);
        assertEq(1, depositContract.depositCount());

        vm.prank(alice);
        vm.expectEmit();
        emit Withdrawn(alice, alice, 1 ether);
        vm.expectEmit();
        emit WithdrawalRequested(alice, alice, 2 ether);
        vault.withdraw(3 ether, alice);

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(30 ether, vault.totalAssets());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0, address(vault).balance);

        // simulate widthdrawal from deposit contract
        vm.deal(address(vault), 32 ether);

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(30 ether, vault.totalAssets());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));

        vm.prank(oracle);
        vault.rebalance();

        assertEq(0 ether, vault.totalStaked());
        assertEq(30 ether, vault.totalUnstaked());
        assertEq(30 ether, vault.totalAssets());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(2 ether, vault.totalClaimable());
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

        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));

        // simulate widthdrawal from deposit contract
        vm.deal(address(vault), 32 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 0 ether, 1.5 ether));
        vault.claim(1.5 ether, alice);

        vm.prank(oracle);
        vault.rebalance();

        vm.prank(alice);
        vm.expectEmit();
        emit Claimed(alice, alice, 1.5 ether);
        vault.claim(1.5 ether, alice);

        assertEq(0.5 ether, vault.totalPendingWithdrawal());
        assertEq(0.5 ether, vault.totalClaimable());
        assertEq(0.5 ether, vault.pendingBalanceOf(alice));
        assertEq(0.5 ether, vault.claimableBalanceOf(alice));

        vm.prank(alice);
        vm.expectEmit();
        emit Claimed(alice, alice, 0.5 ether);
        vault.claim(0.5 ether, alice);

        assertEq(0, vault.totalPendingWithdrawal());
        assertEq(0, vault.totalClaimable());
        assertEq(0, vault.pendingBalanceOf(alice));
        assertEq(0, vault.claimableBalanceOf(alice));
    }

    function test_MultipleWithdrawals() public {
        vm.prank(owner);
        vault.setDepositLimit(1000 ether);

        vm.prank(owner);
        vault.enableOracle(oracle, true);

        address alice = vm.addr(100);
        vm.deal(alice, 1000 ether);

        vm.prank(alice);
        vault.deposit{value: 10 * 32 ether}(alice);

        assertEq(10 * 32 ether, vault.totalAssets());
        assertEq(0 ether, vault.totalStaked());
        assertEq(10 * 32 ether, vault.totalUnstaked());
        assertEq(0 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.balanceOf(alice));
        assertEq(0 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(10 * 32 ether, address(vault).balance);

        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(oracle);
            vault.registerValidator(abi.encodePacked(bytes32(i)), abi.encodePacked(bytes32(11 - i)), bytes32(0));
        }

        assertEq(10 * 32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());

        vm.prank(alice);
        vault.withdraw(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, alice);

        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(10 * 32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, address(vault).balance);

        // simulate widthdrawal from deposit contract +2
        vm.deal(address(vault), 2 * 32 ether);

        vm.prank(oracle);
        vault.rebalance();

        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(8 * 32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(2 * 32 ether, vault.totalClaimable());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(2 * 32 ether, vault.claimableBalanceOf(alice));
        assertEq(2 * 32 ether, address(vault).balance);

        // simulate widthdrawal from deposit contract +5
        vm.deal(address(vault), 7 * 32 ether);

        vm.prank(oracle);
        vault.rebalance();

        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(3 * 32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(7 * 32 ether, vault.totalClaimable());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(10 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(7 * 32 ether, vault.claimableBalanceOf(alice));
        assertEq(7 * 32 ether, address(vault).balance);

        // claim
        vm.prank(alice);
        vm.expectEmit();
        emit Claimed(alice, alice, 4 * 32 ether);
        vault.claim(4 * 32 ether, alice);

        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(3 * 32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(6 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(3 * 32 ether, vault.totalClaimable());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(6 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(3 * 32 ether, vault.claimableBalanceOf(alice));
        assertEq(3 * 32 ether, address(vault).balance);

        // simulate widthdrawal from deposit contract +3
        vm.deal(address(vault), 6 * 32 ether);

        vm.prank(oracle);
        vault.rebalance();

        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(0 ether, vault.totalStaked());
        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalUnstaked());
        assertEq(6 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(6 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalClaimable());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(6 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(6 * 32 ether - _MINIMUM_REQUIRED_SHARES, vault.claimableBalanceOf(alice));
        assertEq(6 * 32 ether, address(vault).balance);
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

        assertEq(0 ether, vault.totalStaked());
        assertEq(79 ether, vault.totalUnstaked());
        assertEq(79 ether, vault.totalAssets());
        assertEq(33 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(46 ether, vault.balanceOf(bob));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(79 ether, address(vault).balance);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        vm.prank(oracle);
        vault.registerValidator(hex"4321", hex"8765", bytes32(0));

        assertEq(64 ether, vault.totalStaked());
        assertEq(15 ether, vault.totalUnstaked());
        assertEq(79 ether, vault.totalAssets());
        assertEq(33 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(46 ether, vault.balanceOf(bob));
        assertEq(0, vault.totalFees());
        assertEq(2, vault.totalValidatorsRegistered());
        assertEq(15 ether, address(vault).balance);

        // simulate rewards + 11 ether
        vm.deal(address(vault), 26 ether);

        vm.prank(oracle);
        vm.expectEmit();
        emit RewardsDistributed(79 ether, 11 ether, 1.1 ether);
        vm.expectEmit();
        emit Rebalanced(64 ether, 15 ether, 64 ether, 24.9 ether);
        vault.rebalance();

        assertEq(64 ether, vault.totalStaked());
        assertEq(24.9 ether, vault.totalUnstaked());
        assertEq(88.9 ether, vault.totalAssets());
        assertEq(79 ether, vault.totalShares());
        assertEq(37.135443037974682418 ether, vault.balanceOf(alice));
        assertEq(51.764556962025316455 ether, vault.balanceOf(bob));
        assertEq(1.1 ether, vault.totalFees());
        assertEq(2, vault.totalValidatorsRegistered());
        assertEq(26 ether, address(vault).balance);

        vm.prank(alice);
        vault.withdraw(37.135443037974682418 ether, alice);

        vm.prank(bob);
        vault.withdraw(51.764556962025316455 ether, bob);

        vm.prank(feeRecipient);
        vm.expectEmit();
        emit FeeClaimed(feeRecipient, feeRecipient, 1.1 ether);
        vault.claimFees(1.1 ether, feeRecipient);

        assertEq(0, vault.totalFees());
        assertEq(0 ether, address(vault).balance);
        assertEq(1.1 ether, feeRecipient.balance);
    }

    function test_DistributeFeesAfterPartialWithdrawal() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 32 ether);
        vm.prank(alice);
        vault.deposit{value: 32 ether}(alice);

        assertEq(0 ether, vault.totalStaked());
        assertEq(32 ether, vault.totalUnstaked());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(32 ether, address(vault).balance);

        vm.prank(oracle);
        vault.registerValidator(hex"11", hex"11", bytes32(0));

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0 ether, address(vault).balance);

        vm.prank(alice);
        vault.withdraw(2 ether, alice);

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0 ether, address(vault).balance);

        // simulate withdrawal + rewards
        vm.deal(address(vault), 33 ether);

        vm.prank(oracle);
        vm.expectEmit();
        emit RewardsDistributed(32 ether, 1 ether, 0.1 ether);
        vm.expectEmit();
        emit Rebalanced(32 ether, 0 ether, 0 ether, 30.9 ether);
        vault.rebalance();

        assertEq(0 ether, vault.totalStaked());
        assertEq(30.9 ether, vault.totalUnstaked());
        assertEq(30.89999999999999897 ether, vault.balanceOf(alice));
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(2 ether, vault.claimableBalanceOf(alice));
        assertEq(0.1 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(33 ether, address(vault).balance);
    }

    function test_DistributeFeesDuringPartialWithdrawal() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 32 ether);
        vm.prank(alice);
        vault.deposit{value: 32 ether}(alice);

        assertEq(0 ether, vault.totalStaked());
        assertEq(32 ether, vault.totalUnstaked());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(32 ether, address(vault).balance);

        vm.prank(oracle);
        vault.registerValidator(hex"11", hex"11", bytes32(0));

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0 ether, address(vault).balance);

        vm.prank(alice);
        vault.withdraw(2 ether, alice);

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0 ether, address(vault).balance);

        // simulate rewards
        vm.deal(address(vault), 3 ether);

        vm.prank(oracle);
        vm.expectEmit();
        emit RewardsDistributed(32 ether, 3 ether, 0.3 ether);
        vm.expectEmit();
        emit Rebalanced(32 ether, 0 ether, 32 ether, 2.7 ether);
        vault.rebalance();

        assertEq(32 ether, vault.totalStaked());
        assertEq(2.7 ether, vault.totalUnstaked());
        assertEq(32.69999999999999891 ether, vault.balanceOf(alice));
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0.3 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(3 ether, address(vault).balance);
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

        assertEq(0 ether, vault.totalStaked());
        assertEq(26 ether, vault.totalUnstaked());
        assertEq(26 ether, vault.totalShares());
        assertEq(10 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(16 ether, vault.balanceOf(bob));
        assertEq(26 ether, address(vault).balance);

        // 50% rewards
        vm.deal(address(vault), 39 ether);

        vm.prank(oracle);
        vault.rebalance();

        assertEq(0 ether, vault.totalStaked());
        assertEq(39 ether, vault.totalUnstaked());
        assertEq(26 ether, vault.totalShares());
        assertEq(15 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(24 ether, vault.balanceOf(bob));
        assertEq(39 ether, address(vault).balance);

        vm.deal(bob, 15 ether);
        vm.prank(bob);
        vault.deposit{value: 15 ether}(bob);

        assertEq(0 ether, vault.totalStaked());
        assertEq(54 ether, vault.totalUnstaked());
        assertEq(15 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
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

        assertEq(0 ether, vault.totalStaked());
        assertEq(54 ether, vault.totalUnstaked());
        assertEq(54 ether, vault.totalAssets());
        assertEq(15 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(39 ether, vault.balanceOf(bob));
        assertEq(54 ether, address(vault).balance);
        assertEq(0 ether, bob.balance);

        vm.prank(bob);
        vault.withdraw(9 ether, bob);

        assertEq(0 ether, vault.totalStaked());
        assertEq(45 ether, vault.totalUnstaked());
        assertEq(45 ether, vault.totalAssets());
        assertEq(15 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(30 ether, vault.balanceOf(bob));
        assertEq(45 ether, address(vault).balance);
        assertEq(9 ether, bob.balance);
    }

    function test_AccountAfterPartialWithdrawal() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 64 ether);
        vm.prank(alice);
        vault.deposit{value: 64 ether}(alice);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        vm.prank(oracle);
        vault.registerValidator(hex"4321", hex"8765", bytes32(0));

        assertEq(0 ether, address(vault).balance);
        assertEq(64 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(64 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));

        vm.prank(alice);
        vault.withdraw(2 ether, alice);

        assertEq(0 ether, address(vault).balance);
        assertEq(64 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(62 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        // simulate withdrawal of 1 validator
        vm.deal(address(vault), 32 ether);

        vm.prank(oracle);
        vault.rebalance();

        assertEq(32 ether, address(vault).balance);
        assertEq(32 ether, vault.totalStaked());
        assertEq(30 ether, vault.totalUnstaked());
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(62 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.pendingBalanceOf(alice));
        assertEq(2 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
    }

    function test_AccountAfterPartialWithdrawalWithPartialDeposit() public {
        vm.startPrank(owner);
        vault.setDepositLimit(124 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 64 ether);
        vm.prank(alice);
        vault.deposit{value: 64 ether}(alice);

        address bob = vm.addr(101);
        vm.deal(bob, 60 ether);
        vm.prank(bob);
        vault.deposit{value: 32 ether}(bob);

        vm.prank(oracle);
        vault.registerValidator(hex"11", hex"11", bytes32(0));

        vm.prank(oracle);
        vault.registerValidator(hex"22", hex"22", bytes32(0));

        vm.prank(oracle);
        vault.registerValidator(hex"33", hex"33", bytes32(0));

        assertEq(0 ether, address(vault).balance);
        assertEq(96 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(0 ether, vault.totalPendingWithdrawal());
        assertEq(64 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(32 ether, vault.balanceOf(bob));

        vm.prank(alice);
        vault.withdraw(6 ether, alice);

        assertEq(0 ether, address(vault).balance);
        assertEq(96 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(6 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(58 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(32 ether, vault.balanceOf(bob));

        vm.prank(bob);
        vault.deposit{value: 28 ether}(bob);

        assertEq(28 ether, address(vault).balance);
        assertEq(96 ether, vault.totalStaked());
        assertEq(28 ether, vault.totalUnstaked());
        assertEq(6 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(58 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(60 ether, vault.balanceOf(bob));

        // simulate withdrawal
        vm.deal(address(vault), 28 ether + 32 ether);

        assertEq(60 ether, address(vault).balance);
        assertEq(96 ether, vault.totalStaked());
        assertEq(28 ether, vault.totalUnstaked());
        assertEq(6 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(58 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(60 ether, vault.balanceOf(bob));

        vm.prank(oracle);
        vm.expectEmit();
        emit Rebalanced(96 ether, 28 ether, 64 ether, 54 ether);
        vault.rebalance();

        assertEq(60 ether, address(vault).balance);
        assertEq(64 ether, vault.totalStaked());
        assertEq(54 ether, vault.totalUnstaked());
        assertEq(6 ether, vault.totalPendingWithdrawal());
        assertEq(6 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
        assertEq(58 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(60 ether, vault.balanceOf(bob));
    }

    function test_RegisterValidatorAfterPartialWithdrawl() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 34 ether);
        vm.prank(alice);
        vault.deposit{value: 32 ether}(alice);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(0 ether, address(vault).balance);
        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(0 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.prank(alice);
        vault.withdraw(2 ether, alice);

        // simulate withdrawal of 1 validator
        vm.deal(address(vault), 32 ether);

        assertEq(32 ether, address(vault).balance);
        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        // deposit 2 more ether to register validator
        vm.prank(alice);
        vault.deposit{value: 2 ether}(alice);

        assertEq(34 ether, address(vault).balance);
        assertEq(32 ether, vault.totalStaked());
        assertEq(2 ether, vault.totalUnstaked());
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 2 ether, 32 ether));
        vault.registerValidator(hex"4321", hex"8765", bytes32(0));

        vm.prank(oracle);
        vault.rebalance();

        assertEq(34 ether, address(vault).balance);
        assertEq(0 ether, vault.totalStaked());
        assertEq(32 ether, vault.totalUnstaked());
        assertEq(2 ether, vault.totalPendingWithdrawal());
        assertEq(2 ether, vault.totalClaimable());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(2 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.prank(oracle);
        vault.registerValidator(hex"4321", hex"8765", bytes32(0));
    }

    function test_AccountAfterPartialWithdrawalOfMultipleValidators() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 96 ether}(alice);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"11", bytes32(0));

        vm.prank(oracle);
        vault.registerValidator(hex"5678", hex"22", bytes32(0));

        vm.prank(oracle);
        vault.registerValidator(hex"9012", hex"33", bytes32(0));

        assertEq(0 ether, address(vault).balance);
        assertEq(96 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(0 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(96 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.prank(alice);
        vault.withdraw(66 ether, alice);

        assertEq(0 ether, address(vault).balance);
        assertEq(96 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(66 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(66 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        // simulate withdrawal of validator
        vm.deal(address(vault), 32 ether);

        assertEq(32 ether, address(vault).balance);
        assertEq(96 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(66 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(66 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.prank(oracle);
        vault.rebalance();

        assertEq(32 ether, address(vault).balance);
        assertEq(64 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(66 ether, vault.totalPendingWithdrawal());
        assertEq(32 ether, vault.totalClaimable());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(66 ether, vault.pendingBalanceOf(alice));
        assertEq(32 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        // simulate withdrawal of remaining validators
        vm.deal(address(vault), 96 ether);

        vm.prank(oracle);
        vault.rebalance();

        assertEq(96 ether, address(vault).balance);
        assertEq(0 ether, vault.totalStaked());
        assertEq(30 ether, vault.totalUnstaked());
        assertEq(66 ether, vault.totalPendingWithdrawal());
        assertEq(66 ether, vault.totalClaimable());
        assertEq(30 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(66 ether, vault.pendingBalanceOf(alice));
        assertEq(66 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
    }

    function test_AccountAfterPartialWithdrawalCoveredByRewards() public {
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

        assertEq(0 ether, vault.totalStaked());
        assertEq(33 ether, vault.totalUnstaked());
        assertEq(33 ether, vault.totalAssets());
        assertEq(33 ether, vault.totalShares());
        assertEq(33 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(33 ether, address(vault).balance);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(32 ether, vault.totalStaked());
        assertEq(1 ether, vault.totalUnstaked());
        assertEq(33 ether, vault.totalAssets());
        assertEq(33 ether, vault.totalShares());
        assertEq(33 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(1 ether, address(vault).balance);

        vm.prank(alice);
        vault.withdraw(1.5 ether, alice);

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(31.5 ether, vault.totalAssets());
        assertEq(31.5 ether, vault.totalShares());
        assertEq(31.5 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0 ether, address(vault).balance);

        assertEq(0.5 ether, vault.totalPendingWithdrawal());
        assertEq(0.5 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(1 ether, alice.balance);

        // simulate rewards not enough to cover withdrawal
        vm.deal(address(vault), 0.4 ether);

        vm.prank(oracle);
        vm.expectEmit();
        emit RewardsDistributed(32 ether, 0.4 ether, 0.04 ether);
        vm.expectEmit();
        emit Rebalanced(32 ether, 0 ether, 32 ether, 0.36 ether);
        vault.rebalance();

        assertEq(32 ether, vault.totalStaked());
        assertEq(0.36 ether, vault.totalUnstaked());
        assertEq(31.86 ether, vault.totalAssets());
        assertEq(31.86 ether - vault.balanceOf(address(0)) - 1, /* rounding error */ vault.balanceOf(alice));
        assertEq(0.04 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0.4 ether, address(vault).balance);

        assertEq(0.5 ether, vault.totalPendingWithdrawal());
        assertEq(0.5 ether, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(1 ether, alice.balance);

        // simulate rewards and withdrawal enough to cover withdrawal
        vm.deal(address(vault), 32.7 ether);

        vm.prank(oracle);
        vm.expectEmit();
        emit RewardsDistributed(32.36 ether, 0.3 ether, 0.03 ether);
        vm.expectEmit();
        emit Rebalanced(32 ether, 0.36 ether, 0 ether, 32.13 ether);
        vault.rebalance();

        assertEq(0 ether, vault.totalStaked());
        assertEq(32.13 ether, vault.totalUnstaked());
        assertEq(32.13 ether, vault.totalAssets());
        assertEq(31.5 ether, vault.totalShares());
        assertEq(32.13 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0.07 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(32.7 ether, address(vault).balance);

        assertEq(0.5 ether, vault.totalPendingWithdrawal());
        assertEq(0.5 ether, vault.pendingBalanceOf(alice));
        assertEq(0.5 ether, vault.claimableBalanceOf(alice));
        assertEq(1 ether, alice.balance);
    }

    function test_AccountAfterFullWithdrawalCoveredByRewards() public {
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

        assertEq(_MINIMUM_REQUIRED_SHARES, vault.balanceOf(address(0)));
        assertEq(0 ether, vault.totalStaked());
        assertEq(33 ether, vault.totalUnstaked());
        assertEq(33 ether, vault.totalAssets());
        assertEq(33 ether, vault.totalShares());
        assertEq(33 ether - _MINIMUM_REQUIRED_SHARES, vault.balanceOf(alice));
        assertEq(0, vault.totalValidatorsRegistered());
        assertEq(33 ether, address(vault).balance);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(32 ether, vault.totalStaked());
        assertEq(1 ether, vault.totalUnstaked());
        assertEq(33 ether, vault.totalAssets());
        assertEq(33 ether, vault.totalShares());
        assertEq(33 ether - _MINIMUM_REQUIRED_SHARES, vault.balanceOf(alice));
        assertEq(0, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(1 ether, address(vault).balance);

        vm.startPrank(alice);
        vault.withdraw(33 ether - _MINIMUM_REQUIRED_SHARES, alice);
        vm.stopPrank();

        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalShares());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(0, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(0 ether, address(vault).balance);

        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(1 ether, alice.balance);

        // simulate rewards matching withdrawal
        vm.deal(address(vault), 32.7 ether);

        vm.startPrank(oracle);
        vm.expectEmit();
        emit RewardsDistributed(32 ether, 0.7 ether, 0.07 ether);
        vm.expectEmit();
        emit Rebalanced(32 ether, 0 ether, 0 ether, 0.63 ether + vault.balanceOf(address(0)));
        vault.rebalance();
        vm.stopPrank();

        assertEq(0 ether, vault.totalStaked());
        assertEq(0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.totalUnstaked());
        assertEq(0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(_MINIMUM_REQUIRED_SHARES, vault.totalShares());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(0.07 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(32.7 ether, address(vault).balance);

        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.claimableBalanceOf(alice));
        assertEq(1 ether, alice.balance);

        // simulate withdrawal
        vm.deal(address(vault), 32.7 ether + 32 ether);

        vm.startPrank(oracle);
        vm.expectEmit();
        emit RewardsDistributed(0.63 ether + _MINIMUM_REQUIRED_SHARES, 32 ether, 3.2 ether);
        vm.expectEmit();
        emit Rebalanced(
            0 ether, 0.63 ether + _MINIMUM_REQUIRED_SHARES, 0 ether, 28.8 ether + 0.63 ether + _MINIMUM_REQUIRED_SHARES
        );
        vault.rebalance();
        vm.stopPrank();

        assertEq(0 ether, vault.totalStaked());
        assertEq(28.8 ether + 0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.totalUnstaked());
        assertEq(28.8 ether + 0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(3.2 ether + 0.07 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(64.7 ether, address(vault).balance);

        assertEq(28.8 ether + 0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.balanceOf(address(0)));
        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalPendingWithdrawal());
        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.pendingBalanceOf(alice));
        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.totalClaimable());
        assertEq(32 ether - _MINIMUM_REQUIRED_SHARES, vault.claimableBalanceOf(alice));
        assertEq(1 ether, alice.balance);

        // claim
        vm.startPrank(alice);
        vm.expectEmit();
        emit Claimed(alice, alice, 32 ether - _MINIMUM_REQUIRED_SHARES);
        vault.claim(32 ether - _MINIMUM_REQUIRED_SHARES, alice);
        vm.stopPrank();

        assertEq(0 ether, vault.totalStaked());
        assertEq(28.8 ether + 0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.totalUnstaked());
        assertEq(28.8 ether + 0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.totalAssets());
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(3.2 ether + 0.07 ether, vault.totalFees());
        assertEq(1, vault.totalValidatorsRegistered());
        assertEq(32.7 ether + _MINIMUM_REQUIRED_SHARES, address(vault).balance);

        assertEq(28.8 ether + 0.63 ether + _MINIMUM_REQUIRED_SHARES, vault.balanceOf(address(0)));
        assertEq(0 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.pendingBalanceOf(alice));
        assertEq(0, vault.totalClaimable());
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(1 ether + 32 ether - _MINIMUM_REQUIRED_SHARES, alice.balance);
    }

    function test_AccountAfterWithdrawalAndDeposit() public {
        vm.startPrank(owner);
        vault.setDepositLimit(100 ether);
        vault.enableOracle(oracle, true);
        vm.stopPrank();

        address alice = vm.addr(100);
        vm.deal(alice, 32 ether);
        vm.prank(alice);
        vault.deposit{value: 32 ether}(alice);

        vm.prank(oracle);
        vault.registerValidator(hex"1234", hex"5678", bytes32(0));

        assertEq(0 ether, address(vault).balance);
        assertEq(32 ether, vault.totalStaked());
        assertEq(0 ether, vault.totalUnstaked());
        assertEq(0 ether, vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.balanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.startPrank(alice);
        vault.withdraw(32 ether - vault.balanceOf(address(0)), alice);
        vm.stopPrank();

        address bob = vm.addr(101);
        vm.deal(bob, 32 ether);
        vm.prank(bob);
        vault.deposit{value: 32 ether}(bob);

        assertEq(32 ether, address(vault).balance);
        assertEq(32 ether, vault.totalStaked());
        assertEq(32 ether, vault.totalUnstaked());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(32 ether, vault.balanceOf(bob));
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(32 ether - vault.balanceOf(address(0)), vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.startPrank(oracle);
        vm.expectEmit();
        emit Rebalanced(32 ether, 32 ether, 32 ether, 32 ether);
        vault.rebalance();
        vm.stopPrank();

        assertEq(32 ether, address(vault).balance);
        assertEq(32 ether, vault.totalStaked());
        assertEq(32 ether, vault.totalUnstaked());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.totalPendingWithdrawal());
        assertEq(0 ether, vault.totalClaimable());
        assertEq(32 ether, vault.balanceOf(bob));
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(32 ether - vault.balanceOf(address(0)), vault.pendingBalanceOf(alice));
        assertEq(0 ether, vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());

        vm.deal(address(vault), 64 ether);

        vm.startPrank(oracle);
        vm.expectEmit();
        emit Rebalanced(32 ether, 32 ether, 0 ether, 32 ether + vault.balanceOf(address(0)));
        vault.rebalance();
        vm.stopPrank();

        assertEq(64 ether, address(vault).balance);
        assertEq(0 ether, vault.totalStaked());
        assertEq(32 ether + vault.balanceOf(address(0)), vault.totalUnstaked());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.totalPendingWithdrawal());
        assertEq(32 ether - vault.balanceOf(address(0)), vault.totalClaimable());
        assertEq(32 ether, vault.balanceOf(bob));
        assertEq(0 ether, vault.balanceOf(alice));
        assertEq(32 ether - vault.balanceOf(address(0)), vault.pendingBalanceOf(alice));
        assertEq(32 ether - vault.balanceOf(address(0)), vault.claimableBalanceOf(alice));
        assertEq(0 ether, vault.totalFees());
    }

    function test_InflationAttack() public {
        vm.startPrank(owner);
        vault.setDepositLimit(1_000_000 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        address alice = vm.addr(100);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalShares(), 0);
        assertEq(vault.sharesOf(alice), 0);
        assertEq(vault.balanceOf(alice), 0 ether);

        // Alice - Attacker simply deposits 100 wie
        vm.deal(alice, 1_000_000 ether);
        vm.prank(alice);
        vault.deposit{value: _MINIMUM_REQUIRED_SHARES + 1 wei}(alice);

        assertNotEq(vault.totalAssets(), 0);
        assertNotEq(vault.totalShares(), 0);
        assertNotEq(vault.sharesOf(alice), 0);
        assertNotEq(vault.balanceOf(alice), 0);

        // simulate rewards - reward injection
        vm.deal(address(vault), 1 ether);

        // vault rebalance - reward accounting
        vm.prank(oracle);
        vault.rebalance();

        uint256 withdraw_amount = vault.balanceOf(alice) - 2;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidAmount.selector, withdraw_amount));
        vault.withdraw(withdraw_amount, alice);

        assertNotEq(vault.totalAssets(), 0);
        assertNotEq(vault.totalShares(), 0);
        assertEq(vault.sharesOf(alice), 1);
        assertNotEq(vault.balanceOf(alice), 0);

        for (uint256 i; i < 65; i++) {
            vm.prank(alice);
            // ignore reverts due deposit limits
            try vault.deposit{value: vault.totalAssets() - 1}(alice) {} catch {}
        }

        uint256 aliceShares = vault.sharesOf(alice);
        uint256 aliceBalance = vault.balanceOf(alice);

        address bob = vm.addr(111);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vault.deposit{value: 1 ether}(bob);

        assertEq(vault.sharesOf(alice), aliceShares);
        assertTrue(aliceBalance <= vault.balanceOf(alice));
        assertNotEq(vault.sharesOf(bob), 0);
        assertTrue(
            vault.balanceOf(bob) >= 1 ether - 1e15 /* rounding error of 18 decimals - 3 of minimum shares amount */
        );
    }

    function test_TransferStake() public {
        vm.startPrank(owner);
        vault.setDepositLimit(1_000_000 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        address alice = vm.addr(100);
        address bob = vm.addr(101);

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}(alice);

        uint256 balance = vault.balanceOf(alice);
        assertEq(0, vault.balanceOf(bob));

        vm.prank(alice);
        vm.expectEmit();
        emit StakeTransferred(alice, bob, balance, "0x1234");
        vault.transferStake(bob, balance, "0x1234");

        assertEq(0, vault.balanceOf(alice));
        assertEq(balance, vault.balanceOf(bob));
        assertEq(0, bob.balance);

        vm.prank(bob);
        vault.withdraw(balance, bob);

        assertEq(balance, bob.balance);
        assertEq(0, vault.balanceOf(bob));
        assertEq(0, vault.balanceOf(alice));
    }

    function test_Revert_TransferStake() public {
        vm.startPrank(owner);
        vault.setDepositLimit(1_000_000 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        address alice = vm.addr(100);
        address bob = vm.addr(101);

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}(alice);

        uint256 balance = vault.balanceOf(alice);
        assertEq(0, vault.balanceOf(bob));

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 0, balance));
        vault.transferStake(bob, balance, "0x1234");

        assertEq(0, vault.balanceOf(bob));
        assertEq(balance, vault.balanceOf(alice));
    }

    function test_NotifyAfterStakeTransferred() public {
        vm.startPrank(owner);
        vault.setDepositLimit(1_000_000 ether);
        vault.enableOracle(oracle, true);
        vault.setFee(10_000);
        vault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        MockStakeRecipient recipient = new MockStakeRecipient();

        address alice = vm.addr(100);

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}(alice);

        uint256 balance = vault.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit();
        emit StakeTransferred(alice, address(recipient), balance, "0x1234");
        vault.transferStake(address(recipient), balance, "0x1234");

        assertEq(0, vault.sharesOf(alice));
        assertEq(0, vault.balanceOf(alice));

        assertEq(alice, recipient.lastFrom());
        assertEq(address(vault), recipient.lastSender());
        assertEq(balance, recipient.lastAmount());
        assertEq("0x1234", recipient.lastData());
    }
}

contract MockStakeRecipient is ERC165, IVaultStakeRecipient {
    address public lastFrom;
    uint256 public lastAmount;
    bytes public lastData;
    address public lastSender;

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IVaultStakeRecipient).interfaceId || super.supportsInterface(interfaceId);
    }

    function onVaultStakeReceived(address from, uint256 amount, bytes calldata data) external override {
        lastSender = msg.sender;
        lastFrom = from;
        lastAmount = amount;
        lastData = data;
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
