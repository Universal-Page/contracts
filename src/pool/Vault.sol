// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DepositContract, DEPOSIT_AMOUNT} from "./Deposit.sol";

contract Vault is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable {
    error InvalidAmount(uint256 amount);
    error WithdrawalFailed(address account, address beneficiary, uint256 amount);
    error ClaimFailed(address account, address beneficiary, uint256 amount);
    error DepositLimitExceeded(uint256 totalValue, uint256 depositLimit);
    error CallerNotOracle(address account);
    error InsufficientBalance(uint256 availableAmount, uint256 requestedAmount);

    event Deposited(address indexed account, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed account, address indexed beneficiary, uint256 amount);
    event WithdrawalRequested(address indexed account, address indexed beneficiary, uint256 amount);
    event Claimed(address indexed account, address indexed beneficiary, uint256 amount);
    event DepositLimitChanged(uint256 previousLimit, uint256 newLimit);

    uint256 public depositLimit;
    uint256 public totalShares;
    uint256 public totalAmount;
    uint256 public availableAmount;
    uint256 public pendingWithdrawalAmount;
    uint256 public validators;
    mapping(address => uint256) private _shares;
    mapping(address => bool) private _oracles;
    mapping(address => uint256) private _pendingWithdrawals;

    modifier onlyOracle() {
        _checkOracle();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        _setOwner(newOwner_);
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

    function setDepositLimit(uint256 newDepositLimit) external onlyOwner {
        uint256 previousDepositLimit = depositLimit;
        depositLimit = newDepositLimit;
        emit DepositLimitChanged(previousDepositLimit, newDepositLimit);
    }

    function enableOracle(address oracle, bool enabled) external onlyOwner {
        _oracles[oracle] = enabled;
    }

    function isOracle(address oracle) public view returns (bool) {
        return _oracles[oracle];
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
        uint256 shares = _shares[account];
        uint256 amount = shares > 0 ? Math.mulDiv(shares, totalAmount, totalShares) : 0;
        return amount;
    }

    function pendingBalanceOf(address account) external view returns (uint256) {
        return _pendingWithdrawals[account];
    }

    function claim(uint256 amount, address beneficiary) external nonReentrant whenNotPaused {
        address account = msg.sender;
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (amount > _pendingWithdrawals[account]) {
            revert InsufficientBalance(_pendingWithdrawals[account], amount);
        }
        _pendingWithdrawals[account] -= amount;
        pendingWithdrawalAmount -= amount;
        (bool success,) = beneficiary.call{value: amount}("");
        if (!success) {
            revert ClaimFailed(account, beneficiary, amount);
        }
        emit Claimed(account, beneficiary, amount);
    }

    function deposit(address beneficiary) public payable whenNotPaused {
        address account = msg.sender;
        uint256 amount = msg.value;
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (totalAmount + amount > depositLimit) {
            revert DepositLimitExceeded(totalAmount + amount, depositLimit);
        }
        uint256 shares = totalAmount == 0 ? amount : Math.mulDiv(amount, totalShares, totalAmount);
        _shares[beneficiary] += shares;
        totalShares += shares;
        totalAmount += amount;
        emit Deposited(account, beneficiary, amount);
    }

    function withdraw(uint256 shares, address beneficiary) external nonReentrant whenNotPaused {
        address account = msg.sender;
        if (shares == 0) {
            revert InvalidAmount(shares);
        }
        if (shares > _shares[account]) {
            revert InsufficientBalance(_shares[account], shares);
        }

        uint256 amount = Math.mulDiv(shares, totalAmount, totalShares);
        _shares[account] -= shares;
        totalShares -= shares;
        totalAmount -= amount;

        uint256 immediateAmount = amount > availableAmount ? availableAmount : amount;
        uint256 delayedAmount = amount - immediateAmount;

        if (immediateAmount > 0) {
            availableAmount -= immediateAmount;
            (bool success,) = beneficiary.call{value: immediateAmount}("");
            if (!success) {
                revert WithdrawalFailed(account, beneficiary, immediateAmount);
            }
            emit Withdrawn(account, beneficiary, immediateAmount);
        }

        if (delayedAmount > 0) {
            pendingWithdrawalAmount += delayedAmount;
            _pendingWithdrawals[beneficiary] += delayedAmount;
            emit WithdrawalRequested(account, beneficiary, delayedAmount);
        }
    }

    function rebalance() external onlyOracle whenNotPaused {
        _rebalance();
    }

    function _rebalance() private {
        uint256 currentBalance = address(this).balance;
        availableAmount = currentBalance > pendingWithdrawalAmount ? currentBalance - pendingWithdrawalAmount : 0;
        totalAmount = validators * DEPOSIT_AMOUNT + availableAmount;
    }

    function registerValidator(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot)
        external
        onlyOracle
        nonReentrant
        whenNotPaused
    {
        // rebalance before depositing
        _rebalance();
        if (availableAmount < DEPOSIT_AMOUNT) {
            revert InsufficientBalance(availableAmount, DEPOSIT_AMOUNT);
        }
        validators += 1;
        bytes memory withdrawalCredentials = abi.encodePacked(hex"010000000000000000000000", address(this));
        DepositContract.deposit{value: DEPOSIT_AMOUNT}(pubkey, withdrawalCredentials, signature, depositDataRoot);
        // after depositing and registering new validator we need to rebalance again
        _rebalance();
    }
}
