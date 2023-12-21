// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Vault is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable {
    error InvalidAmount(uint256 amount);
    error WithdrawalFailed(address account, address beneficiary, uint256 amount);
    error DepositLimitExceeded(uint256 totalValue, uint256 depositLimit);

    event Deposited(address indexed account, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed account, address indexed beneficiary, uint256 amount);
    event WithdrawalRequested(address indexed account, address indexed beneficiary, uint256 amount);
    event DepositLimitChanged(uint256 previousDepositLimit, uint256 newDepositLimit);

    uint256 public totalValue;
    uint256 public totalShares;
    uint256 public depositLimit;
    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _withdrawalRequests;

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

    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    function balanceOf(address account) external view returns (uint256) {
        uint256 shares = _shares[account];
        uint256 sharesAmount = totalShares > 0 ? Math.mulDiv(shares, totalValue, totalShares) : 0;
        uint256 withdrawalAmount = _withdrawalRequests[account];
        return sharesAmount + withdrawalAmount;
    }

    function claimableBalanceOf(address account) external view returns (uint256) {
        return _withdrawalRequests[account];
    }

    function claim(uint256 amount, address beneficiary) external nonReentrant whenNotPaused {
        address account = msg.sender;
        uint256 withdrawalAmount = _withdrawalRequests[account];
        if (amount == 0 || amount > withdrawalAmount) {
            revert InvalidAmount(amount);
        }
        _withdrawalRequests[account] -= amount;
        emit Withdrawn(account, beneficiary, amount);
        (bool success,) = beneficiary.call{value: amount}("");
        if (!success) {
            revert WithdrawalFailed(account, beneficiary, amount);
        }
    }

    function deposit(address beneficiary) public payable whenNotPaused {
        address account = msg.sender;
        uint256 amount = msg.value;
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        totalValue += amount;
        if (totalValue > depositLimit) {
            revert DepositLimitExceeded(totalValue, depositLimit);
        }
        uint256 shares = totalShares == 0 ? amount : Math.mulDiv(amount, totalShares, totalValue);
        totalShares += shares;
        _shares[beneficiary] += shares;
        emit Deposited(account, beneficiary, amount);
    }

    function withdraw(uint256 shares, address beneficiary) external nonReentrant whenNotPaused {
        address account = msg.sender;
        _shares[account] -= shares;

        uint256 amount = Math.mulDiv(shares, totalValue, totalShares);
        totalShares -= shares;
        totalValue -= amount;
        emit Withdrawn(account, beneficiary, amount);

        uint256 availableAmount = address(this).balance;
        uint256 immediateAmount = amount > availableAmount ? availableAmount : amount;
        uint256 withdrawalAmount = immediateAmount < amount ? amount - immediateAmount : 0;

        if (withdrawalAmount > 0) {
            _withdrawalRequests[beneficiary] += withdrawalAmount;
            emit WithdrawalRequested(account, beneficiary, withdrawalAmount);
        }

        if (immediateAmount > 0) {
            (bool success,) = beneficiary.call{value: immediateAmount}("");
            if (!success) {
                revert WithdrawalFailed(account, beneficiary, immediateAmount);
            }
        }
    }
}
