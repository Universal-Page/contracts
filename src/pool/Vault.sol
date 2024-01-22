// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IDepositContract, DEPOSIT_AMOUNT} from "./IDepositContract.sol";

contract Vault is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable {
    uint32 private constant _FEE_BASIS = 100_000;

    error InvalidAmount(uint256 amount);
    error WithdrawalFailed(address account, address beneficiary, uint256 amount);
    error ClaimFailed(address account, address beneficiary, uint256 amount);
    error DepositLimitExceeded(uint256 totalValue, uint256 depositLimit);
    error CallerNotOracle(address account);
    error InsufficientBalance(uint256 availableAmount, uint256 requestedAmount);
    error CallerNotFeeRecipient(address account);
    error FeeClaimFailed(address account, address beneficiary, uint256 amount);
    error InvalidAddress(address account);
    error ValidatorAlreadyRegistered(bytes pubkey);

    event Deposited(address indexed account, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed account, address indexed beneficiary, uint256 amount);
    event WithdrawalRequested(address indexed account, address indexed beneficiary, uint256 amount);
    event Claimed(address indexed account, address indexed beneficiary, uint256 amount);
    event DepositLimitChanged(uint256 previousLimit, uint256 newLimit);
    event FeeChanged(uint32 previousFee, uint32 newFee);
    event FeeRecipientChanged(address previousFeeRecipient, address newFeeRecipient);
    event FeeClaimed(address indexed account, address indexed beneficiary, uint256 amount);
    event RewardsDistributed(uint256 balance, uint256 rewards, uint256 fee);
    event OracleEnabled(address indexed oracle, bool enabled);
    event Rebalanced(
        uint256 previousTotalStaked, uint256 previousTotalUnstaked, uint256 totalStaked, uint256 totalUnstaked
    );

    // limit of total deposits in wei.
    // This limits the total number of validators that can be registered.
    uint256 public depositLimit;
    // total number of shares in the vault
    uint256 public totalShares;
    // total amount of active stake in wei on beacon chain
    uint256 public totalStaked;
    // total amount of inactive stake in wei on execution layer
    uint256 public totalUnstaked;
    // total amount of pending withdrawals in wei.
    // This is the amount that is taken from staked balance and may not be immidiately available for withdrawal.
    uint256 public totalPendingWithdrawal;
    // Total number of ever registered validators
    uint256 public validators;
    // Vault fee in parts per 100,000
    uint32 public fee;
    // Recipient of the vault fee
    address public feeRecipient;
    // Total amount of fees available for withdrawal
    uint256 public totalFees;
    // Whether only allowlisted accounts can deposit
    bool public restricted;
    IDepositContract private _depositContract;
    mapping(address => uint256) private _shares;
    mapping(address => bool) private _oracles;
    mapping(address => uint256) private _pendingWithdrawals;
    mapping(address => bool) private _allowlisted;
    mapping(bytes => bool) private _registeredKeys;
    // Total amount of pending withdrawals that can be claimed immidiately
    uint256 public totalClaimable;

    modifier onlyOracle() {
        _checkOracle();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_, IDepositContract depositContract_) external initializer {
        if (address(depositContract_) == address(0)) {
            revert InvalidAddress(address(depositContract_));
        }
        __ReentrancyGuard_init();
        __Pausable_init();
        _setOwner(newOwner_);
        _depositContract = depositContract_;
    }

    receive() external payable {
        deposit(msg.sender);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setFee(uint32 newFee) external onlyOwner {
        if (newFee > _FEE_BASIS) {
            revert InvalidAmount(newFee);
        }
        uint32 previousFee = fee;
        fee = newFee;
        emit FeeChanged(previousFee, newFee);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) {
            revert InvalidAddress(newFeeRecipient);
        }
        address previousFeeRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;
        emit FeeRecipientChanged(previousFeeRecipient, newFeeRecipient);
    }

    function setDepositLimit(uint256 newDepositLimit) external onlyOwner {
        uint256 previousDepositLimit = depositLimit;
        depositLimit = newDepositLimit;
        emit DepositLimitChanged(previousDepositLimit, newDepositLimit);
    }

    function enableOracle(address oracle, bool enabled) external onlyOwner {
        _oracles[oracle] = enabled;
        emit OracleEnabled(oracle, enabled);
    }

    function isOracle(address oracle) public view returns (bool) {
        return _oracles[oracle];
    }

    function allowlist(address account, bool enabled) external onlyOwner {
        _allowlisted[account] = enabled;
    }

    function isAllowlisted(address account) public view returns (bool) {
        return _allowlisted[account];
    }

    function setRestricted(bool enabled) external onlyOwner {
        restricted = enabled;
    }

    function _checkOracle() private view {
        address oracle = msg.sender;
        if (!isOracle(oracle)) {
            revert CallerNotOracle(oracle);
        }
    }

    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    function balanceOf(address account) external view returns (uint256) {
        return _toBalance(_shares[account]);
    }

    function pendingBalanceOf(address account) external view returns (uint256) {
        return _pendingWithdrawals[account];
    }

    function claimableBalanceOf(address account) external view returns (uint256) {
        uint256 pendingWithdrawal = _pendingWithdrawals[account];
        return pendingWithdrawal > totalClaimable ? totalClaimable : pendingWithdrawal;
    }

    function claim(uint256 amount, address beneficiary) external nonReentrant whenNotPaused {
        if (beneficiary == address(0)) {
            revert InvalidAddress(beneficiary);
        }
        address account = msg.sender;
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (amount > _pendingWithdrawals[account]) {
            revert InsufficientBalance(_pendingWithdrawals[account], amount);
        }
        if (amount > totalClaimable) {
            revert InsufficientBalance(totalClaimable, amount);
        }
        _pendingWithdrawals[account] -= amount;
        totalPendingWithdrawal -= amount;
        totalClaimable -= amount;
        (bool success,) = beneficiary.call{value: amount}("");
        if (!success) {
            revert ClaimFailed(account, beneficiary, amount);
        }
        emit Claimed(account, beneficiary, amount);
    }

    function _toBalance(uint256 shares) private view returns (uint256) {
        if (totalShares == 0) {
            return 0;
        }
        // In some cases, totalShares may be slightly less than totalStaked + totalUnstaked due to rounding errors.
        // The error is 1 wei considered insignificant and can be ignored.
        return Math.mulDiv(shares, totalStaked + totalUnstaked, totalShares);
    }

    function _toShares(uint256 amount) private view returns (uint256) {
        if (totalShares == 0) {
            return amount;
        }
        return Math.mulDiv(amount, totalShares, totalStaked + totalUnstaked);
    }

    function deposit(address beneficiary) public payable whenNotPaused {
        if (beneficiary == address(0)) {
            revert InvalidAddress(beneficiary);
        }
        address account = msg.sender;
        if (restricted && !isAllowlisted(account)) {
            revert InvalidAddress(account);
        }
        uint256 amount = msg.value;
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        uint256 newTotalDeposits = Math.max(validators * DEPOSIT_AMOUNT, totalStaked + totalUnstaked) + amount;
        if (newTotalDeposits > depositLimit) {
            revert DepositLimitExceeded(newTotalDeposits, depositLimit);
        }
        uint256 shares = _toShares(amount);
        _shares[beneficiary] += shares;
        totalShares += shares;
        totalUnstaked += amount;
        emit Deposited(account, beneficiary, amount);
    }

    function withdraw(uint256 amount, address beneficiary) external nonReentrant whenNotPaused {
        if (beneficiary == address(0)) {
            revert InvalidAddress(beneficiary);
        }
        address account = msg.sender;
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        uint256 shares = _toShares(amount);
        if (shares > _shares[account]) {
            revert InsufficientBalance(_shares[account], shares);
        }
        _shares[account] -= shares;
        totalShares -= shares;

        uint256 immediateAmount = amount > totalUnstaked ? totalUnstaked : amount;
        uint256 delayedAmount = amount - immediateAmount;

        totalUnstaked -= immediateAmount;
        totalStaked -= delayedAmount;
        totalPendingWithdrawal += delayedAmount;
        _pendingWithdrawals[beneficiary] += delayedAmount;

        if (immediateAmount > 0) {
            (bool success,) = beneficiary.call{value: immediateAmount}("");
            if (!success) {
                revert WithdrawalFailed(account, beneficiary, immediateAmount);
            }
            emit Withdrawn(account, beneficiary, immediateAmount);
        }

        if (delayedAmount > 0) {
            emit WithdrawalRequested(account, beneficiary, delayedAmount);
        }
    }

    function claimFees(uint256 amount, address beneficiary) external nonReentrant whenNotPaused {
        if (beneficiary == address(0)) {
            revert InvalidAddress(beneficiary);
        }
        address account = msg.sender;
        if (account != feeRecipient) {
            revert CallerNotFeeRecipient(account);
        }
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (amount > totalFees) {
            revert InsufficientBalance(totalFees, amount);
        }
        totalFees -= amount;
        (bool success,) = beneficiary.call{value: amount}("");
        if (!success) {
            revert FeeClaimFailed(account, beneficiary, amount);
        }
        emit FeeClaimed(account, beneficiary, amount);
    }

    function rebalance() external onlyOracle whenNotPaused {
        uint256 unstaked = address(this).balance;
        uint256 staked = totalStaked;
        uint256 claimable;

        // account for staking fees
        unstaked = unstaked < totalFees ? 0 : unstaked - totalFees;

        // account for pending withdrawals to claim later.
        if (totalPendingWithdrawal > unstaked) {
            claimable = unstaked;
            unstaked = 0;
        } else {
            claimable = totalPendingWithdrawal;
            unstaked -= totalPendingWithdrawal;
        }

        // calculate inactive part of staked balance.
        // In a case of a partial withdrawal, the inactive part will be redistributed to unstaked balance.
        // This only happens when full withdrawal is completed and deposited back into the contract.
        uint256 inactive = staked % DEPOSIT_AMOUNT;
        if (unstaked >= totalUnstaked + inactive) {
            // redistribute inactive stake from staked to unstaked balance only if there is sufficient unstaked balance
            staked -= inactive;
        }

        // at this point the difference represents the rewards.
        // if the difference is positive, it means that the rewards are available for distribution.
        if (staked + unstaked > totalStaked + totalUnstaked) {
            uint256 rewards = staked + unstaked - totalStaked - totalUnstaked;
            uint256 feeAmount = Math.mulDiv(rewards, fee, _FEE_BASIS);
            emit RewardsDistributed(totalStaked + totalUnstaked, rewards, feeAmount);
            totalFees += feeAmount;
            unstaked -= feeAmount;
        }

        emit Rebalanced(totalStaked, totalUnstaked, staked, unstaked);
        totalClaimable = claimable;
        totalUnstaked = unstaked;
        totalStaked = staked;
    }

    function isValidatorRegistered(bytes calldata pubkey) external view returns (bool) {
        return _registeredKeys[pubkey];
    }

    function registerValidator(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot)
        external
        onlyOracle
        nonReentrant
        whenNotPaused
    {
        if ((validators + 1) * DEPOSIT_AMOUNT > depositLimit) {
            revert DepositLimitExceeded((validators + 1) * DEPOSIT_AMOUNT, depositLimit);
        }
        if (totalUnstaked < DEPOSIT_AMOUNT) {
            revert InsufficientBalance(totalUnstaked, DEPOSIT_AMOUNT);
        }
        if (_registeredKeys[pubkey]) {
            revert ValidatorAlreadyRegistered(pubkey);
        }
        _registeredKeys[pubkey] = true;
        validators += 1;
        totalStaked += DEPOSIT_AMOUNT;
        totalUnstaked -= DEPOSIT_AMOUNT;
        bytes memory withdrawalCredentials = abi.encodePacked(hex"010000000000000000000000", address(this));
        _depositContract.deposit{value: DEPOSIT_AMOUNT}(pubkey, withdrawalCredentials, signature, depositDataRoot);
    }
}
