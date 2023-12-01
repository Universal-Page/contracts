// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {LSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {LSP8CappedSupply} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8CappedSupply.sol";
import {LSP8Enumerable} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8Enumerable.sol";
import {LSP8IdentifiableDigitalAssetCore} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAssetCore.sol";
import {_LSP8_TOKENID_SCHEMA_UNIQUE_ID} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {Withdrawable} from "../../common/Withdrawable.sol";
import {ICollectorIdentifiableDigitalAsset} from "./ICollectorIdentifiableDigitalAsset.sol";

contract CollectorIdentifiableDigitalAsset is
    ICollectorIdentifiableDigitalAsset,
    LSP8IdentifiableDigitalAsset,
    LSP8CappedSupply,
    LSP8Enumerable,
    Pausable,
    ReentrancyGuard,
    Withdrawable
{
    error TokenSupplyLimitExceeded(uint256 supply, uint256 limit, uint256 amount);
    error InvalidPurchaseAmount(uint256 required, uint256 amount);
    error InvalidTokenSupplyCap(uint256 cap);
    error InvalidTokenSupplyLimit(uint256 limit);
    error InvalidController();
    error UnauthorizedPurchase(address recipient, bytes32[] tokenIds, uint256 totalPrice);
    error InvalidTokenId(bytes32 tokenId);

    event TokensPurchased(address indexed recipient, bytes32[] tokenIds, uint256 totalPaid);
    event TokenSupplyLimitChanged(uint256 limit);
    event PriceChanged(uint256 price);
    event TokensReserved(address indexed recipient, bytes32[] tokenIds);
    event ControllerChanged(address indexed oldController, address indexed newController);

    mapping(uint256 => bool) private _reservedTokenIds;
    address public controller;
    uint256 public override price;
    uint256 public override tokenSupplyLimit;

    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        address controller_,
        uint256 tokenSupplyCap_
    )
        LSP8IdentifiableDigitalAsset(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_SCHEMA_UNIQUE_ID)
        LSP8CappedSupply(tokenSupplyCap_)
    {
        _setController(controller_);
    }

    receive() external payable override(LSP8IdentifiableDigitalAsset, Withdrawable) {
        _doReceive();
    }

    function tokenTierOf(bytes32 tokenId) external view override returns (uint8 tier) {
        _existsOrError(tokenId);
        tier = uint8(uint256(tokenId) & 0x3);
    }

    function tokenIndexOf(bytes32 tokenId) public view override returns (uint256 index) {
        _existsOrError(tokenId);
        index = uint256(tokenId) >> 4;
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

    function setPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        emit PriceChanged(newPrice);
    }

    function setTokenSupplyLimit(uint256 limit) external onlyOwner {
        if (limit < tokenSupplyLimit || limit > tokenSupplyCap()) {
            revert InvalidTokenSupplyLimit(limit);
        }
        tokenSupplyLimit = limit;
        emit TokenSupplyLimitChanged(limit);
    }

    function reserve(address recipient, bytes32[] calldata tokenIds) external onlyOwner {
        uint256 amount = tokenIds.length;
        uint256 supply = totalSupply();
        if (supply + amount > tokenSupplyLimit) {
            revert TokenSupplyLimitExceeded(supply, tokenSupplyLimit, amount);
        }
        for (uint256 i = 0; i < amount;) {
            _mint(recipient, tokenIds[i], true, "");
            unchecked {
                i++;
            }
        }
        emit TokensReserved(recipient, tokenIds);
    }

    function purchase(address recipient, bytes32[] calldata tokenIds, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        bytes32 hash = keccak256(abi.encodePacked(address(this), block.chainid, recipient, tokenIds, msg.value));
        if (ECDSA.recover(hash, v, r, s) != controller) {
            revert UnauthorizedPurchase(recipient, tokenIds, msg.value);
        }
        uint256 amount = tokenIds.length;
        uint256 supply = totalSupply();
        if (supply + amount > tokenSupplyLimit) {
            revert TokenSupplyLimitExceeded(supply, tokenSupplyLimit, amount);
        }
        if (msg.value != amount * price) {
            revert InvalidPurchaseAmount(amount * price, msg.value);
        }
        for (uint256 i = 0; i < amount;) {
            _mint(recipient, tokenIds[i], false, "");
            unchecked {
                i++;
            }
        }
        emit TokensPurchased(recipient, tokenIds, msg.value);
    }

    function _mint(address to, bytes32 tokenId, bool allowNonLSP1Recipient, bytes memory data)
        internal
        virtual
        override(LSP8IdentifiableDigitalAssetCore, LSP8CappedSupply)
    {
        super._mint(to, tokenId, allowNonLSP1Recipient, data);
        uint256 index = tokenIndexOf(tokenId);
        if (_reservedTokenIds[index]) {
            revert InvalidTokenId(tokenId);
        }
        _reservedTokenIds[index] = true;
    }

    function _beforeTokenTransfer(address from, address to, bytes32 tokenId, bytes memory data)
        internal
        virtual
        override(LSP8IdentifiableDigitalAssetCore, LSP8Enumerable)
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, tokenId, data);
    }
}
