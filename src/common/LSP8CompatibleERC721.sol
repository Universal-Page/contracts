// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {IERC721Metadata, IERC721} from "@openzeppelin/contracts/interfaces/IERC721Metadata.sol";
import {BytesLib} from "solidity-bytes-utils/contracts/BytesLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LSP1Utils} from "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1Utils.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    LSP8IdentifiableDigitalAssetCore,
    LSP8IdentifiableDigitalAsset
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {
    LSP8NotTokenOwner,
    LSP8CannotUseAddressZeroAsOperator,
    LSP8TokenOwnerCannotBeOperator,
    LSP8OperatorAlreadyAuthorized,
    LSP8NotTokenOperator
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Errors.sol";
import {
    _LSP4_METADATA_KEY,
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY
} from "@lukso/lsp-smart-contracts/contracts/LSP4DigitalAssetMetadata/LSP4Constants.sol";
import {
    _LSP8_TOKEN_METADATA_BASE_URI,
    _LSP8_TOKENID_FORMAT_KEY,
    _LSP8_TOKENID_FORMAT_NUMBER,
    _LSP8_TOKENID_FORMAT_STRING,
    _LSP8_TOKENID_FORMAT_ADDRESS,
    _LSP8_TOKENID_FORMAT_UNIQUE_ID,
    _LSP8_TOKENID_FORMAT_HASH
} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8Constants.sol";

abstract contract LSP8CompatibleERC721 is IERC721Metadata, LSP8IdentifiableDigitalAsset {
    using BytesLib for bytes;
    using EnumerableSet for EnumerableSet.AddressSet;
    using LSP1Utils for address;

    mapping(address => mapping(address => bool)) private _operatorApprovals;

    constructor(
        string memory name_,
        string memory symbol_,
        address newOwner_,
        uint256 lsp4TokenType_,
        uint256 lsp8TokenIdFormat_
    ) LSP8IdentifiableDigitalAsset(name_, symbol_, newOwner_, lsp4TokenType_, lsp8TokenIdFormat_) {}

    function name() public view virtual override returns (string memory) {
        bytes memory data = _getData(_LSP4_TOKEN_NAME_KEY);
        return string(data);
    }

    function symbol() public view virtual override returns (string memory) {
        bytes memory data = _getData(_LSP4_TOKEN_SYMBOL_KEY);
        return string(data);
    }

    function balanceOf(address tokenOwner)
        public
        view
        virtual
        override(IERC721, LSP8IdentifiableDigitalAssetCore)
        returns (uint256)
    {
        return super.balanceOf(tokenOwner);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, LSP8IdentifiableDigitalAsset)
        returns (bool)
    {
        return interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC721Metadata).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        // per token metadata if available
        {
            bytes memory data = _getDataForTokenId(bytes32(tokenId), _LSP4_METADATA_KEY);
            if (data.length != 0) {
                // bytes2(identifier) + bytes4(method) + bytes2(verificationDataLength) + bytes(verificationData)
                uint256 offset = 8 + data.toUint16(6);
                string memory tokenUri = string(data.slice(offset, data.length - offset));
                return tokenUri;
            }
        }

        // reconstruct token uri
        bytes memory baseUriData = _getData(_LSP8_TOKEN_METADATA_BASE_URI);
        if (baseUriData.length == 0) {
            return "";
        }
        // bytes2(identifier) + bytes4(method) + bytes2(verificationDataLength) + bytes(verificationData)
        uint256 baseUriOffset = 8 + baseUriData.toUint16(6);
        bytes memory baseUri = baseUriData.slice(baseUriOffset, baseUriData.length - baseUriOffset);

        uint256 tokenIdFormat = _getData(_LSP8_TOKENID_FORMAT_KEY).toUint256(0);
        if (tokenIdFormat == _LSP8_TOKENID_FORMAT_NUMBER) {
            return string(BytesLib.concat(baseUri, bytes(Strings.toString(tokenId))));
        } else if (tokenIdFormat == _LSP8_TOKENID_FORMAT_STRING) {
            return string(BytesLib.concat(baseUri, abi.encodePacked(tokenId)));
        } else if (tokenIdFormat == _LSP8_TOKENID_FORMAT_ADDRESS) {
            return string(BytesLib.concat(baseUri, bytes(Strings.toHexString(tokenId, 20))));
        } else if (tokenIdFormat == _LSP8_TOKENID_FORMAT_UNIQUE_ID || tokenIdFormat == _LSP8_TOKENID_FORMAT_HASH) {
            return string(BytesLib.concat(baseUri, bytes(Strings.toHexString(tokenId, 32))));
        } else {
            return string(baseUri);
        }
    }

    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        return tokenOwnerOf(bytes32(tokenId));
    }

    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        bytes32 tokenIdAsBytes32 = bytes32(tokenId);
        _existsOrError(tokenIdAsBytes32);

        address[] memory operatorsForTokenId = getOperatorsOf(tokenIdAsBytes32);
        uint256 operatorListLength = operatorsForTokenId.length;

        if (operatorListLength == 0) {
            return address(0);
        } else {
            // Read the last added operator authorized to provide "best" compatibility.
            // In ERC721 there is one operator address at a time for a tokenId, so multiple calls to
            // `approve` would cause `getApproved` to return the last added operator. In this
            // compatibility version the same is true, when the authorized operators were not previously
            // authorized. If addresses are removed, then `getApproved` returned address can change due
            // to implementation of `EnumberableSet._remove`.
            return operatorsForTokenId[operatorListLength - 1];
        }
    }

    function isApprovedForAll(address tokenOwner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }

    function approve(address operator, uint256 tokenId) public virtual override {
        authorizeOperator(operator, bytes32(tokenId), "");
    }

    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        _transfer(from, to, bytes32(tokenId), true, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        _safeTransfer(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
        _safeTransfer(from, to, tokenId, data);
    }

    function authorizeOperator(address operator, bytes32 tokenId, bytes memory operatorNotificationData)
        public
        virtual
        override
    {
        address tokenOwner = tokenOwnerOf(tokenId);

        if (tokenOwner != msg.sender && !isApprovedForAll(tokenOwner, msg.sender)) {
            revert LSP8NotTokenOwner(tokenOwner, tokenId, msg.sender);
        }

        if (operator == address(0)) {
            revert LSP8CannotUseAddressZeroAsOperator();
        }

        if (tokenOwner == operator) {
            revert LSP8TokenOwnerCannotBeOperator();
        }

        bool isAdded = _operators[tokenId].add(operator);
        if (!isAdded) revert LSP8OperatorAlreadyAuthorized(operator, tokenId);

        emit OperatorAuthorizationChanged(operator, tokenOwner, tokenId, operatorNotificationData);
        emit Approval(tokenOwnerOf(tokenId), operator, uint256(tokenId));

        bytes memory lsp1Data = abi.encode(
            msg.sender,
            tokenId,
            true, // authorized
            operatorNotificationData
        );

        _notifyTokenOperator(operator, lsp1Data);
    }

    function _transfer(address from, address to, bytes32 tokenId, bool force, bytes memory data)
        internal
        virtual
        override
    {
        if (!isApprovedForAll(from, msg.sender) && !_isOperatorOrOwner(msg.sender, tokenId)) {
            revert LSP8NotTokenOperator(tokenId, msg.sender);
        }

        emit Transfer(from, to, uint256(tokenId));
        super._transfer(from, to, tokenId, force, data);
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, bytes32(tokenId), true, data);
        require(
            _checkOnERC721Received(from, to, tokenId, data),
            "LSP8CompatibleERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _mint(address to, bytes32 tokenId, bool force, bytes memory data) internal virtual override {
        emit Transfer(address(0), to, uint256(tokenId));
        super._mint(to, tokenId, force, data);
    }

    function _burn(bytes32 tokenId, bytes memory data) internal virtual override {
        address tokenOwner = tokenOwnerOf(tokenId);

        emit Transfer(tokenOwner, address(0), uint256(tokenId));
        super._burn(tokenId, data);
    }

    function _setApprovalForAll(address tokensOwner, address operator, bool approved) internal virtual {
        require(tokensOwner != operator, "LSP8CompatibleERC721: approve to caller");
        _operatorApprovals[tokensOwner][operator] = approved;
        emit ApprovalForAll(tokensOwner, operator, approved);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
        private
        returns (bool)
    {
        if (to.code.length == 0) {
            return true;
        }

        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert("LSP8CompatibleERC721: transfer to non ERC721Receiver implementer");
            } else {
                // solhint-disable no-inline-assembly
                /// @solidity memory-safe-assembly
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }
}
