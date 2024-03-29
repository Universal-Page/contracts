// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

struct Nomination {
    uint256 amount;
    bytes data;
    bytes32[] delegations;
}

struct Delegation {
    address delegator;
    uint256 amount;
    bool bound;
}

bytes32 constant ELECTIONS_CURATOR_ROLE = keccak256("ELECTIONS_CURATOR_ROLE");

contract Elections is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable {
    uint8 private constant _MAX_SLOTS = 5;
    uint256 private constant _SLOT_DURATION = 3 days;
    uint256 private constant _MIN_NOMINATION_PRICE = 0.01 ether;
    uint256 private constant _MIN_DELEGATION_PRICE = 0.01 ether;
    uint8 private constant _MAX_ELECTION_CYCLES = 3;

    error InvalidAmount(uint256 amount, uint256 expected);
    error AlreadyNominated(address nominator, bytes data);
    error Unpaid(address account, uint256 amount);
    error InvalidNomination(address nominator, bytes data);
    error InvalidDelegation(address delegatee, address delegator, bytes data);
    error RoleNotGranted(address account, bytes32 role);
    error RoleUnchanged(address account, bytes32 role);
    error NotOpenElection(uint256 nextElectionTime);
    error Electing();

    event Nominated(address indexed nominator, uint256 amount, bytes data);
    event Retracted(address indexed nominator, uint256 amount, bytes data);
    event Elected(address indexed nominator, uint256 nominatedAmount, uint256 delegatedAmount, bytes data);
    event Undelegated(address indexed nominator, address indexed delegator, uint256 amount, bytes data);
    event Delegated(address indexed delegatee, address indexed delegator, uint256 amount, bytes data);
    event RoleGranted(address indexed account, bytes32 role);
    event RoleRevoked(address indexed account, bytes32 role);
    event ClaimedElected(address indexed account, uint256 amount, address indexed beneficiary);

    mapping(bytes32 role => mapping(address account => bool granted)) private _roles;
    mapping(bytes32 nominationKey => Nomination) private _nominations;
    mapping(bytes32 delegationKey => Delegation) private _delegations;
    uint256 public electionTime;
    uint256 public electedAmount;

    modifier onlyRole(bytes32 role) {
        if (!hasRole(msg.sender, role)) {
            revert RoleNotGranted(msg.sender, role);
        }
        _;
    }

    modifier whenNotElecting() {
        if (block.timestamp >= electionTime) {
            revert Electing();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        _setOwner(newOwner_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function hasRole(address account, bytes32 role) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(address account, bytes32 role) external onlyOwner {
        _grantRole(account, role);
    }

    function revokeRole(address account, bytes32 role) external onlyOwner {
        _revokeRole(account, role);
    }

    function _grantRole(address account, bytes32 role) internal {
        if (hasRole(account, role)) {
            revert RoleUnchanged(account, role);
        }
        _roles[role][account] = true;
        emit RoleGranted(account, role);
    }

    function _revokeRole(address account, bytes32 role) internal {
        if (!hasRole(account, role)) {
            revert RoleUnchanged(account, role);
        }
        _roles[role][account] = false;
        emit RoleRevoked(account, role);
    }

    function _nominatorKey(address nominator, bytes calldata data) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(nominator, data));
    }

    function _delegationKey(address delegator, bytes32 nomitationKey) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(delegator, nomitationKey));
    }

    function nominate(bytes calldata data) external payable whenNotPaused nonReentrant {
        address nominator = msg.sender;
        uint256 amount = msg.value;
        if (amount < _MIN_NOMINATION_PRICE) {
            revert InvalidAmount({amount: amount, expected: _MIN_NOMINATION_PRICE});
        }
        bytes32 nominationKey = _nominatorKey(nominator, data);
        Nomination memory nomination = _nominations[nominationKey];
        if (nomination.amount > 0) {
            revert AlreadyNominated(nominator, data);
        }
        _nominations[nominationKey] = Nomination({amount: amount, data: data, delegations: new bytes32[](0)});
        emit Nominated(nominator, amount, data);
    }

    function retract(bytes calldata data) external whenNotPaused whenNotElecting nonReentrant {
        address nominator = msg.sender;
        bytes32 nominationKey = _nominatorKey(nominator, data);

        Nomination memory nomination = _nominations[nominationKey];
        if (nomination.amount == 0) {
            revert InvalidNomination(nominator, data);
        }
        _nominations[nominationKey].amount = 0;

        // Retract all delegations
        for (uint256 i = 0; i < nomination.delegations.length; i++) {
            bytes32 delegationKey = nomination.delegations[i];
            _delegations[delegationKey].bound = false;
            Delegation memory delegation = _delegations[delegationKey];
            if (delegation.amount > 0) {
                _delegations[delegationKey].amount = 0;
                emit Undelegated(nominator, delegation.delegator, delegation.amount, data);
                (bool undelegated,) = delegation.delegator.call{value: delegation.amount}("");
                if (!undelegated) {
                    revert Unpaid(delegation.delegator, delegation.amount);
                }
            }
        }

        emit Retracted(nominator, nomination.amount, data);
        (bool retracted,) = nominator.call{value: nomination.amount}("");
        if (!retracted) {
            revert Unpaid(nominator, nomination.amount);
        }
    }

    function delegate(address delegatee, bytes calldata data) external payable whenNotPaused nonReentrant {
        address delegator = msg.sender;
        bytes32 nominationKey = _nominatorKey(delegatee, data);
        bytes32 delegationKey = _delegationKey(delegator, nominationKey);

        uint256 amount = msg.value;
        if (amount < _MIN_DELEGATION_PRICE) {
            revert InvalidAmount({amount: amount, expected: _MIN_DELEGATION_PRICE});
        }

        Nomination storage nomination = _nominations[nominationKey];
        if (nomination.amount == 0) {
            revert InvalidNomination(delegatee, data);
        }

        Delegation storage delegation = _delegations[delegationKey];
        delegation.delegator = delegator;
        delegation.amount += amount;
        if (!delegation.bound) {
            delegation.bound = true;
            nomination.delegations.push(delegationKey);
        }
        emit Delegated(delegatee, delegator, amount, data);
    }

    function undelegate(address delegatee, bytes calldata data) external whenNotPaused whenNotElecting nonReentrant {
        address delegator = msg.sender;
        bytes32 nominationKey = _nominatorKey(delegatee, data);
        bytes32 delegationKey = _delegationKey(delegator, nominationKey);
        Delegation memory delegation = _delegations[delegationKey];
        if (delegation.amount == 0) {
            revert InvalidDelegation(delegatee, delegator, data);
        }
        _delegations[delegationKey].amount = 0;
        emit Undelegated(delegatee, delegator, delegation.amount, data);
        (bool undelegated,) = delegator.call{value: delegation.amount}("");
        if (!undelegated) {
            revert Unpaid(delegator, delegation.amount);
        }
    }

    function elect(address nominator, bytes calldata data)
        external
        whenNotPaused
        nonReentrant
        onlyRole(ELECTIONS_CURATOR_ROLE)
    {
        uint256 timestamp = block.timestamp;
        if (timestamp < electionTime) {
            revert NotOpenElection(electionTime);
        }
        electionTime = timestamp + _SLOT_DURATION;

        bytes32 nominationKey = _nominatorKey(nominator, data);
        Nomination storage nomination = _nominations[nominationKey];
        if (nomination.amount == 0) {
            revert InvalidNomination(nominator, data);
        }
        uint256 nominatedAmount = nomination.amount;
        nomination.amount = 0;

        uint256 delegatedAmount = 0;
        for (uint256 i = 0; i < nomination.delegations.length; i++) {
            bytes32 delegationKey = nomination.delegations[i];
            Delegation storage delegation = _delegations[delegationKey];
            delegatedAmount += delegation.amount;
            delegation.amount = 0;
            delegation.bound = false;
        }

        electedAmount += nominatedAmount + delegatedAmount;
        emit Elected(nominator, nominatedAmount, delegatedAmount, data);
    }

    function claimElected(uint256 amount, address beneficiary) external onlyOwner {
        if (amount > electedAmount) {
            revert InvalidAmount({amount: amount, expected: electedAmount});
        }
        electedAmount -= amount;
        emit ClaimedElected(msg.sender, amount, beneficiary);
        (bool claimed,) = beneficiary.call{value: amount}("");
        if (!claimed) {
            revert Unpaid(beneficiary, amount);
        }
    }
}
