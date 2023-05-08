// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";
import {IndexedDrop} from "../../common/IndexedDrop.sol";

contract DigitalAssetDrop is OwnableUnset, ReentrancyGuard, IndexedDrop {
    event Claimed(uint256 indexed index, address indexed recipient, uint256 amount);
    event Disposed(address indexed beneficiary, uint256 amount);

    error InvalidBeneficiary(address beneficiary);

    ILSP7DigitalAsset public immutable asset;

    constructor(ILSP7DigitalAsset asset_, bytes32 root_, address owner_) {
        require(address(asset_) != address(0), "asset is zero");
        require(root_ != 0, "root is zero");
        require(owner_ != address(0), "owner is zero");
        asset = asset_;
        _setRoot(root_);
        _setOwner(owner_);
    }

    function isClaimed(uint256 index) external view returns (bool) {
        return _isClaimed(index);
    }

    function claim(bytes32[] calldata proof, uint256 index, address recipient, uint256 amount) external nonReentrant {
        _claim(proof, index, abi.encode(msg.sender, amount));
        emit Claimed(index, recipient, amount);
        asset.transfer(address(this), recipient, amount, false, "");
    }

    function dispose(address beneficiary) external onlyOwner nonReentrant {
        if (beneficiary == address(0)) {
            revert InvalidBeneficiary(beneficiary);
        }
        uint256 amount = asset.balanceOf(address(this));
        emit Disposed(beneficiary, amount);
        asset.transfer(address(this), beneficiary, amount, true, "");
    }
}
