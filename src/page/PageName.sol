// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

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
import {IPageNameMarketplace, PendingSale} from "./IPageNameMarketplace.sol";

contract PageName is LSP8EnumerableInitAbstract, ReentrancyGuardUpgradeable, PausableUpgradeable, Withdrawable {
    error InvalidController();

    error UnauthorizedRelease(address account, bytes32 tokenId);

    error IncorrectReservationName(address recipient, string name);
    error UnauthorizedReservation(address recipient, string name, uint256 price);

    error TransferExceedLimit(address from, address to, bytes32 tokenId, uint256 limit);
    error TransferInvalidSale(address from, address to, bytes32 tokenId, uint256 totalPaid);

    event ControllerChanged(address indexed oldController, address indexed newController);

    event ReservedName(address indexed account, bytes32 indexed tokenId, uint256 price);
    event ReleasedName(address indexed account, bytes32 indexed tokenId);

    mapping(address => uint256) private _profileLimit;
    uint256 public price;
    uint8 public minimumLength;
    uint16 public profileLimit;
    address public controller;
    IPageNameMarketplace public marketplace;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        address beneficiary_,
        address controller_,
        uint256 price_,
        uint8 minimumLength_,
        uint16 profileLimit_,
        IPageNameMarketplace marketplace_
    ) external initializer {
        super._initialize(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_STRING);
        __ReentrancyGuard_init();
        __Pausable_init();
        _setBeneficiary(beneficiary_);
        _setController(controller_);
        price = price_;
        profileLimit = profileLimit_;
        minimumLength = minimumLength_;
        marketplace = marketplace_;
    }

    receive() external payable override(LSP8IdentifiableDigitalAssetInitAbstract, Withdrawable) {
        _doReceive();
    }

    function setProfileLimit(uint16 newLimit) external onlyOwner {
        profileLimit = newLimit;
    }

    function setMinimumLength(uint8 newLength) external onlyOwner {
        minimumLength = newLength;
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
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

    function profileLimitOf(address tokenOwner) public view returns (uint256) {
        return profileLimit + _profileLimit[tokenOwner];
    }

    function reserve(address recipient, string calldata name, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        bytes32 hash = keccak256(abi.encodePacked(address(this), block.chainid, recipient, name, msg.value));
        if (ECDSA.recover(hash, v, r, s) != controller) {
            revert UnauthorizedReservation(recipient, name, msg.value);
        }
        if (!_isValidName(name)) {
            revert IncorrectReservationName(recipient, name);
        }
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

    function _beforeTokenTransfer(address from, address to, bytes32 tokenId, bytes memory data)
        internal
        virtual
        override(LSP8EnumerableInitAbstract)
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, tokenId, data);
        if (from != address(0) && to != address(0) && balanceOf(to) >= profileLimitOf(to)) {
            if (msg.sender == address(marketplace)) {
                PendingSale memory sale = marketplace.pendingSale();
                if (sale.asset == address(this) && sale.tokenId == tokenId && sale.seller == from && sale.buyer == to) {
                    if (sale.totalPaid < price) {
                        revert TransferInvalidSale(from, to, tokenId, sale.totalPaid);
                    }
                } else {
                    revert TransferInvalidSale(from, to, tokenId, 0);
                }
            } else {
                revert TransferExceedLimit(from, to, tokenId, profileLimitOf(to));
            }
        }
    }
}
