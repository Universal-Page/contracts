// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {_LSP8_TOKENID_FORMAT_STRING} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {LSP8EnumerableInitAbstract} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8EnumerableInitAbstract.sol";
import {LSP8IdentifiableDigitalAssetInitAbstract} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAssetInitAbstract.sol";
import {Withdrawable} from "../common/Withdrawable.sol";

contract PageName is LSP8EnumerableInitAbstract, ReentrancyGuardUpgradeable, PausableUpgradeable, Withdrawable {
    uint256 private constant _PROFILE_CLAIMS_CLAIMED = 1 << 255;

    error InvalidController();

    error UnauthorizedRelease(address account, bytes32 tokenId);

    error IncorrectReservationName(address recipient, string name);
    error UnauthorizedReservation(address recipient, string name, uint256 price);

    event ControllerChanged(address indexed oldController, address indexed newController);

    event ReservedName(address indexed account, bytes32 indexed tokenId, uint256 price);
    event ReleasedName(address indexed account, bytes32 indexed tokenId);

    mapping(address => uint256) private _profileClaims;
    uint256 public _unused_storage_slot_1;
    uint8 public minimumLength;
    uint16 public _unused_storage_slot_2;
    address public controller;
    uint160 private _unused_storage_slot_3;
    // hash => used
    mapping(bytes32 => bool) private _usedReservations;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        address beneficiary_,
        address controller_,
        uint8 minimumLength_
    ) external initializer {
        super._initialize(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_STRING);
        __ReentrancyGuard_init();
        __Pausable_init();
        _setBeneficiary(beneficiary_);
        _setController(controller_);
        minimumLength = minimumLength_;
    }

    receive() external payable override(LSP8IdentifiableDigitalAssetInitAbstract, Withdrawable) {
        _doReceive();
    }

    function setMinimumLength(uint8 newLength) external onlyOwner {
        minimumLength = newLength;
    }

    function claimsOf(address account) public view returns (bool claimed) {
        uint256 claims = _profileClaims[account];
        claimed = (claims & _PROFILE_CLAIMS_CLAIMED) == _PROFILE_CLAIMS_CLAIMED;
    }

    function setClaimed(address account, bool claimed) private {
        uint256 claims = _profileClaims[account];
        if (claimed) {
            claims |= _PROFILE_CLAIMS_CLAIMED;
        } else {
            claims &= ~_PROFILE_CLAIMS_CLAIMED;
        }
        _profileClaims[account] = claims;
    }

    function setController(address newController) external onlyOwner {
        _setController(newController);
    }

    function _setController(address newController) private {
        if (newController == address(0)) {
            revert InvalidController();
        }
        address oldController = controller;
        if (oldController == newController) {
            revert InvalidController();
        }
        controller = newController;
        emit ControllerChanged(oldController, newController);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function reserve(
        address recipient,
        string calldata name,
        bool force,
        bytes calldata salt,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable nonReentrant whenNotPaused {
        if (!_isValidName(name)) {
            revert IncorrectReservationName(recipient, name);
        }
        bytes32 hash =
            keccak256(abi.encodePacked(address(this), block.chainid, recipient, name, force, salt, msg.value));
        if (_usedReservations[hash] || (ECDSA.recover(hash, v, r, s) != controller)) {
            revert UnauthorizedReservation(recipient, name, msg.value);
        }
        if (!force && (msg.value == 0)) {
            (bool claimed) = claimsOf(recipient);
            if (claimed) {
                revert UnauthorizedReservation(recipient, name, msg.value);
            }
            setClaimed(recipient, true);
        }
        _usedReservations[hash] = true;
        bytes32 tokenId = bytes32(bytes(name));
        _mint(recipient, tokenId, false, "");
        emit ReservedName(recipient, tokenId, msg.value);
    }

    function release(bytes32 tokenId) external nonReentrant whenNotPaused {
        if (!isOperatorFor(msg.sender, tokenId)) {
            revert UnauthorizedRelease(msg.sender, tokenId);
        }
        address tokenOwner = tokenOwnerOf(tokenId);
        _burn(tokenId, "");
        emit ReleasedName(tokenOwner, tokenId);
    }

    function _isValidName(string memory name) private view returns (bool) {
        bytes memory chars = bytes(name);
        uint256 length = chars.length;
        if (length < minimumLength || length > 32) {
            return false;
        }
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = chars[i];
            if (!(char >= 0x61 && char <= 0x7a) && !(char >= 0x30 && char <= 0x39) && char != 0x2d && char != 0x5f) {
                return false;
            }
        }
        return true;
    }
}
