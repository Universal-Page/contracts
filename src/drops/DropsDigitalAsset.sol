// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IndexedDrop} from "../common/IndexedDrop.sol";
import {Points} from "../common/Points.sol";

abstract contract DropsDigitalAsset is OwnableUnset, ReentrancyGuard, IndexedDrop {
    event Activated();
    event Deactivated();
    event Claimed(address indexed account, address indexed beneficiary, uint256 amount);
    event ConfigurationChanged(uint256 startTime, uint256 mintPrice, uint256 profileMintLimit, bytes32 allowlistRoot);

    error Inactive();
    error ZeroAddress();
    error ZeroAmount();
    error ClaimInvalidAmount(uint256 amount);
    error ProfileMintZeroLimit();
    error InvalidServiceFee(uint256 fee);
    error UnpaidClaim(address account, uint256 amount);
    error MintInvalidSignature();
    error MintInvalidAmount(uint256 amount);
    error MintExceedLimit(uint256 amount);
    error MintDisallowed();
    error InvalidStartTime(uint256 startTime);

    uint32 public immutable serviceFeePoints;
    address public immutable service;
    address public immutable verifier;
    uint256 public startTime;
    uint256 public mintPrice;
    uint256 public profileMintLimit;
    bool public activated;
    mapping(address => uint256) private _balances;

    modifier whenActivate() {
        if (!activated || block.timestamp < startTime) {
            revert Inactive();
        }
        _;
    }

    constructor(address service_, address verifier_, uint32 serviceFeePoints_) {
        if (!Points.isValid(serviceFeePoints_)) {
            revert InvalidServiceFee(serviceFeePoints_);
        }
        if (service_ == address(0) || verifier_ == address(0)) {
            revert ZeroAddress();
        }
        activated = false;
        service = service_;
        verifier = verifier_;
        serviceFeePoints = serviceFeePoints_;
    }

    function allowlist() external view returns (bytes32 aRoot) {
        aRoot = super.root();
    }

    function activate() external onlyOwner {
        _activate();
    }

    function _activate() internal {
        if (!activated) {
            activated = true;
            emit Activated();
        }
    }

    function deactivate() external onlyOwner {
        if (activated) {
            activated = false;
            emit Deactivated();
        }
    }

    function configure(uint256 startTime_, uint256 mintPrice_, uint256 profileMintLimit_, bytes32 allowlistRoot_)
        external
        onlyOwner
    {
        if (startTime_ < block.timestamp) {
            revert InvalidStartTime(startTime_);
        }
        if (profileMintLimit_ == 0) {
            revert ProfileMintZeroLimit();
        }
        startTime = startTime_;
        mintPrice = mintPrice_;
        profileMintLimit = profileMintLimit_;
        _setRoot(allowlistRoot_);
        emit ConfigurationChanged(startTime_, mintPrice_, profileMintLimit_, allowlistRoot_);
    }

    function mint(address recipient, uint256 amount, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        whenActivate
        nonReentrant
    {
        if (_hasRoot()) {
            revert MintDisallowed();
        }
        _mintSigned(recipient, amount, v, r, s);
    }

    function mintAllowlist(
        bytes32[] calldata proof,
        uint256 index,
        address recipient,
        uint256 amount,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable whenActivate nonReentrant {
        _claim(proof, index, abi.encode(msg.sender));
        _mintSigned(recipient, amount, v, r, s);
    }

    function _mintSigned(address recipient, uint256 amount, uint8 v, bytes32 r, bytes32 s) private {
        bytes32 hash = keccak256(abi.encodePacked(address(this), block.chainid, recipient, amount, msg.value));
        if (ECDSA.recover(hash, v, r, s) != verifier) {
            revert MintInvalidSignature();
        }
        uint256 newBalance = balanceOf(recipient) + amount;
        if (newBalance > profileMintLimit) {
            revert MintExceedLimit(newBalance);
        }
        uint256 totalPrice = amount * mintPrice;
        if (msg.value != totalPrice) {
            revert MintInvalidAmount(msg.value);
        }
        uint256 serviceFeeAmount = Points.realize(totalPrice, serviceFeePoints);
        _balances[owner()] += totalPrice - serviceFeeAmount;
        _balances[service] += serviceFeeAmount;
        _doMint(recipient, amount, totalPrice);
    }

    function claimBalanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function claim(address beneficiary, uint256 amount) external nonReentrant {
        if (beneficiary == address(0)) {
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
        (bool success,) = beneficiary.call{value: amount}("");
        if (!success) {
            revert UnpaidClaim(beneficiary, amount);
        }
        emit Claimed(msg.sender, beneficiary, amount);
    }

    function balanceOf(address tokenOwner) public view virtual returns (uint256);

    function _doMint(address recipient, uint256 amount, uint256 totalPrice) internal virtual;
}
