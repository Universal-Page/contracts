// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Points} from "../common/Points.sol";

abstract contract DropsLightAsset is OwnableUnset, ReentrancyGuard {
    event Claimed(address indexed account, address indexed recipient, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error ClaimInvalidAmount(uint256 amount);
    error InvalidServiceFee(uint256 fee);
    error UnpaidClaim(address account, uint256 amount);
    error MintInvalidSignature();
    error MintInvalidAmount(uint256 amount);
    error MintExceedLimit(uint256 amount);

    address public immutable beneficiary;
    uint32 public immutable serviceFeePoints;
    address public immutable service;
    address public immutable verifier;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _mintNonce;

    constructor(address beneficiary_, address service_, address verifier_, uint32 serviceFeePoints_) {
        if (!Points.isValid(serviceFeePoints_)) {
            revert InvalidServiceFee(serviceFeePoints_);
        }
        if (service_ == address(0) || verifier_ == address(0)) {
            revert ZeroAddress();
        }
        beneficiary = beneficiary_;
        service = service_;
        verifier = verifier_;
        serviceFeePoints = serviceFeePoints_;
    }

    function mintNonceOf(address recipient) external view returns (uint256) {
        return _mintNonce[recipient];
    }

    function _useMintNonce(address recipient) internal returns (uint256) {
        return _mintNonce[recipient]++;
    }

    function mint(address recipient, uint256 amount, uint8 v, bytes32 r, bytes32 s) external payable nonReentrant {
        uint256 totalPrice = msg.value;
        bytes32 hash = keccak256(
            abi.encodePacked(address(this), block.chainid, recipient, _useMintNonce(recipient), amount, totalPrice)
        );
        if (ECDSA.recover(hash, v, r, s) != verifier) {
            revert MintInvalidSignature();
        }
        uint256 serviceFeeAmount = Points.realize(totalPrice, serviceFeePoints);
        _balances[beneficiary] += totalPrice - serviceFeeAmount;
        _balances[service] += serviceFeeAmount;
        _doMint(recipient, amount, totalPrice);
    }

    function claimBalanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function claim(address recipient, uint256 amount) external nonReentrant {
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        uint256 balance = _balances[msg.sender];
        if (balance < amount) {
            revert ClaimInvalidAmount(amount);
        }
        _balances[msg.sender] -= amount;
        (bool success,) = recipient.call{value: amount}("");
        if (!success) {
            revert UnpaidClaim(recipient, amount);
        }
        emit Claimed(msg.sender, recipient, amount);
    }

    function balanceOf(address tokenOwner) public view virtual returns (uint256);

    function _doMint(address recipient, uint256 amount, uint256 totalPrice) internal virtual;
}
