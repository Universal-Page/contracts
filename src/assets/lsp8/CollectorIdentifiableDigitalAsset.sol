// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {LSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {LSP8CappedSupply} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8CappedSupply.sol";
import {LSP8Enumerable} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/extensions/LSP8Enumerable.sol";
import {LSP8IdentifiableDigitalAssetCore} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAssetCore.sol";
import {_LSP8_TOKENID_FORMAT_UNIQUE_ID} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {Withdrawable} from "../../common/Withdrawable.sol";
import {ICollectorIdentifiableDigitalAsset} from "./ICollectorIdentifiableDigitalAsset.sol";

contract CollectorIdentifiableDigitalAsset is
    ICollectorIdentifiableDigitalAsset,
    LSP8IdentifiableDigitalAsset,
    LSP8CappedSupply,
    LSP8Enumerable,
    ReentrancyGuard,
    Withdrawable
{
    error InvalidController();
    error UnauthorizedPurchase(address recipient, bytes32[] tokenIds, uint256 totalPrice);
    error InvalidTokenId(bytes32 tokenId);

    event TokensPurchased(address indexed recipient, bytes32[] tokenIds, uint256 totalPaid);
    event ControllerChanged(address indexed oldController, address indexed newController);

    mapping(uint256 => bool) private _reservedTokenIds;
    address public controller;

    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        address controller_,
        uint256 tokenSupplyCap_
    )
        LSP8IdentifiableDigitalAsset(name_, symbol_, newOwner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_UNIQUE_ID)
        LSP8CappedSupply(tokenSupplyCap_)
    {
        _setController(controller_);
    }

    receive() external payable override(LSP8IdentifiableDigitalAsset, Withdrawable) {
        _doReceive();
    }

    function tokenTierOf(bytes32 tokenId) external view override returns (uint8 tier) {
        _existsOrError(tokenId);
        tier = uint8(uint256(tokenId) & 0xF);
    }

    function tokenIndexOf(bytes32 tokenId) public view override returns (uint16 index) {
        _existsOrError(tokenId);
        index = uint16((uint256(tokenId) >> 4) & 0xFFFF);
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

    function purchase(address recipient, bytes32[] calldata tokenIds, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override
        nonReentrant
    {
        bytes32 hash = keccak256(abi.encodePacked(address(this), block.chainid, recipient, tokenIds, msg.value));
        if (ECDSA.recover(hash, v, r, s) != controller) {
            revert UnauthorizedPurchase(recipient, tokenIds, msg.value);
        }
        uint256 amount = tokenIds.length;
        for (uint256 i = 0; i < amount; i++) {
            _mint(recipient, tokenIds[i], true, "");
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
    {
        super._beforeTokenTransfer(from, to, tokenId, data);
    }
}
