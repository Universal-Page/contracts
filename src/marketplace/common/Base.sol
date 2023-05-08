// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Withdrawable} from "../../common/Withdrawable.sol";
import {Points} from "../../common/Points.sol";
import {Royalties, RoyaltiesInfo} from "../../common/Royalties.sol";
import {IParticipant} from "../IParticipant.sol";

abstract contract Base is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable, Withdrawable {
    event FeePointsChanged(uint32 oldPoints, uint32 newPoints);
    event RoyaltiesThresholdPointsChanged(uint32 oldPoints, uint32 newPoints);
    event ParticipantChanged(address indexed oldParticipant, address indexed newParticipant);

    error RoyaltiesExceedThreshold(uint32 royaltiesThresholdPoints, uint256 totalPrice, uint256 totalRoyalties);

    uint32 public feePoints;
    uint32 public royaltiesThresholdPoints;
    IParticipant public participant;

    function _initialize(address newOwner_, address beneficiary_, IParticipant participant_)
        internal
        onlyInitializing
    {
        require(address(participant_) != address(0));
        __ReentrancyGuard_init();
        __Pausable_init();
        _setOwner(newOwner_);
        _setBeneficiary(beneficiary_);
        participant = participant_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setParticipant(IParticipant participant_) external onlyOwner {
        if (address(participant) != address(participant_)) {
            emit ParticipantChanged(address(participant), address(participant_));
            participant = participant_;
        }
    }

    function setFeePoints(uint32 newFeePoints) external onlyOwner {
        require(Points.isValid(newFeePoints));
        if (feePoints != newFeePoints) {
            uint32 old = feePoints;
            feePoints = newFeePoints;
            emit FeePointsChanged(old, newFeePoints);
        }
    }

    function setRoyaltiesThresholdPoints(uint32 newRoyaltiesThresholdPoints) external onlyOwner {
        require(Points.isValid(newRoyaltiesThresholdPoints));
        if (royaltiesThresholdPoints != newRoyaltiesThresholdPoints) {
            uint32 old = royaltiesThresholdPoints;
            royaltiesThresholdPoints = newRoyaltiesThresholdPoints;
            emit RoyaltiesThresholdPointsChanged(old, newRoyaltiesThresholdPoints);
        }
    }

    function _calculateFeeWithDiscount(address seller, uint256 totalPrice) internal view returns (uint256) {
        uint32 discountPoints = Points.multiply(feePoints, participant.feeDiscountFor(seller));
        assert(discountPoints <= feePoints);
        return Points.realize(totalPrice, feePoints - discountPoints);
    }

    function _calculateRoyalties(address asset, uint256 totalPrice)
        internal
        view
        returns (uint256 totalAmount, address[] memory recipients, uint256[] memory amounts)
    {
        totalAmount = 0;
        RoyaltiesInfo[] memory royalties = Royalties.royalties(asset);
        recipients = new address[](royalties.length);
        amounts = new uint256[](royalties.length);
        uint256 count = royalties.length;
        for (uint256 i = 0; i < count; i++) {
            assert(Points.isValid(royalties[i].points));
            uint256 amount = Points.realize(totalPrice, royalties[i].points);
            recipients[i] = royalties[i].recipient;
            amounts[i] = amount;
            totalAmount += amount;
        }
        if ((royaltiesThresholdPoints != 0) && (totalAmount > Points.realize(totalPrice, royaltiesThresholdPoints))) {
            revert RoyaltiesExceedThreshold(royaltiesThresholdPoints, totalPrice, totalAmount);
        }
    }

    // reserved space (100 slots)
    uint256[99] private _base_reserved;
}
