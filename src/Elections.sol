// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {OwnableUnset} from "@erc725/smart-contracts/contracts/custom/OwnableUnset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ILSP7DigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP7DigitalAsset/ILSP7DigitalAsset.sol";

struct Nomination {
    uint256 blockNumber;
    address nominator;
    uint256 amount;
    bytes data;
    uint128 delegations;
    uint256 delegatedAmount;
}

struct Delegation {
    address delegator;
    uint256 amount;
    bytes32 nomination;
    uint128 index;
}

bytes32 constant ELECTIONS_CURATOR_ROLE = keccak256("ELECTIONS_CURATOR_ROLE");

contract Elections is OwnableUnset, ReentrancyGuardUpgradeable, PausableUpgradeable {
    uint256 private constant _MINIMUM_ELECTION_BLOCKS = 5000; // ~16 hours
    uint256 private constant _DELEGATION_THRESHOLD = 1_000; // 0.1%
    uint256 private constant _NOMINATION_EXPIRATION_BLOCKS = 21000; // ~3 days

    error InvalidAmount(uint256 amount, uint256 expected);
    error AlreadyNominated(address nominator, bytes data);
    error Unpaid(address account, uint256 amount);
    error InvalidNomination(address nominator, bytes data);
    error InvalidDelegation(address delegatee, address delegator, bytes data);
    error RoleNotGranted(address account, bytes32 role);
    error RoleUnchanged(address account, bytes32 role);
    error Electing();
    error NotElecting();
    error NominationHasDelegations(address nominator, bytes data);
    error InvalidElectionBlock(uint256 blockNumber);

    event Nominated(address indexed nominator, uint256 amount, bytes data);
    event Elected(address indexed nominator, uint256 nominatedAmount, uint256 delegatedAmount, bytes data);
    event Delegated(address indexed delegatee, address indexed delegator, uint256 amount, bytes data);
    event Undelegated(address indexed nominator, address indexed delegator, uint256 amount, bytes data);
    event Recycled(address indexed account, uint256 amount);
    event RoleGranted(address indexed account, bytes32 role);
    event RoleRevoked(address indexed account, bytes32 role);
    event NominationPriceChanged(uint256 price);
    event DelegationPriceChanged(uint256 price);
    event ElectionScheduled(uint256 blockNumber);

    ILSP7DigitalAsset public electionToken;
    uint256 public electionBlock;
    uint256 public nominationPrice;
    uint256 public delegationPrice;
    uint256 public recycledAmount;
    mapping(bytes32 role => mapping(address account => bool granted)) private _roles;
    mapping(bytes32 nominationKey => Nomination) private _nominations;
    mapping(bytes32 nominationKey => mapping(uint128 index => bytes32 delegationKey)) private _nominationDelegations;
    mapping(bytes32 delegationKey => Delegation) private _delegations;

    modifier onlyRole(bytes32 role) {
        if (!hasRole(msg.sender, role)) {
            revert RoleNotGranted(msg.sender, role);
        }
        _;
    }

    modifier whenNotElecting() {
        _checkNotElecting();
        _;
    }

    modifier whenElecting() {
        _checkElecting();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_, ILSP7DigitalAsset electionToken_) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        _setOwner(newOwner_);
        electionToken = electionToken_;
        electionBlock = block.number;
        nominationPrice = 1 ether;
        delegationPrice = 0.1 ether;
    }

    function isElecting() public view returns (bool) {
        return block.number >= electionBlock;
    }

    function _checkElecting() private view {
        if (!isElecting()) {
            revert NotElecting();
        }
    }

    function _checkNotElecting() private view {
        if (isElecting()) {
            revert Electing();
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setNominationPrice(uint256 newNominationPrice) external onlyOwner {
        nominationPrice = newNominationPrice;
        emit NominationPriceChanged(newNominationPrice);
    }

    function setDelegationPrice(uint256 newDelegationPrice) external onlyOwner {
        delegationPrice = newDelegationPrice;
        emit DelegationPriceChanged(newDelegationPrice);
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

    function _nominatorKey(address nominator, bytes memory data) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(nominator, data));
    }

    function _delegationKey(address delegator, bytes32 nomitationKey) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(delegator, nomitationKey));
    }

    function isNominated(address nominator, bytes calldata data) public view returns (bool) {
        return _nominations[_nominatorKey(nominator, data)].amount > 0;
    }

    function _checkNomination(address nominator, bytes calldata data) private view {
        if (!isNominated(nominator, data)) {
            revert InvalidNomination(nominator, data);
        }
    }

    function nominate(bytes calldata data, uint256 amount)
        external
        payable
        whenNotPaused
        whenNotElecting
        nonReentrant
    {
        address nominator = msg.sender;
        if (amount < nominationPrice) {
            revert InvalidAmount({amount: amount, expected: nominationPrice});
        }
        bytes32 nominationKey = _nominatorKey(nominator, data);
        Nomination memory nomination = _nominations[nominationKey];
        if (nomination.amount > 0) {
            revert AlreadyNominated(nominator, data);
        }

        _nominations[nominationKey] = Nomination({
            blockNumber: block.number,
            nominator: nominator,
            amount: amount,
            data: data,
            delegatedAmount: 0,
            delegations: 0
        });
        electionToken.transfer(nominator, address(this), amount, true, "0x");
        emit Nominated(nominator, amount, data);
    }

    function isDelegated(address delegatee, address delegator, bytes calldata data) public view returns (bool) {
        return _delegations[_delegationKey(delegator, _nominatorKey(delegatee, data))].amount > 0;
    }

    function delegate(address delegatee, bytes calldata data, uint256 amount)
        external
        payable
        whenNotPaused
        whenNotElecting
        nonReentrant
    {
        _checkNomination(delegatee, data);
        if (amount < delegationPrice) {
            revert InvalidAmount({amount: amount, expected: delegationPrice});
        }

        address delegator = msg.sender;
        bytes32 nominationKey = _nominatorKey(delegatee, data);
        bytes32 delegationKey = _delegationKey(delegator, nominationKey);

        Nomination storage nomination = _nominations[nominationKey];
        uint256 amountThreshold = nomination.delegatedAmount * _DELEGATION_THRESHOLD / 100_000;
        if (amount < amountThreshold) {
            revert InvalidAmount({amount: amount, expected: amountThreshold});
        }

        Delegation storage delegation = _delegations[delegationKey];
        delegation.amount += amount;
        nomination.delegatedAmount += amount;

        if (delegation.nomination != nominationKey) {
            delegation.nomination = nominationKey;
            delegation.delegator = delegator;
            delegation.index = nomination.delegations;
            _nominationDelegations[nominationKey][nomination.delegations] = delegationKey;
            nomination.delegations += 1;
        }

        electionToken.transfer(delegator, address(this), amount, true, "0x");
        emit Delegated(delegatee, delegator, amount, data);
    }

    function undelegate(address delegatee, bytes calldata data) external whenNotPaused whenNotElecting nonReentrant {
        _checkNomination(delegatee, data);

        address delegator = msg.sender;
        bytes32 nominationKey = _nominatorKey(delegatee, data);
        bytes32 delegationKey = _delegationKey(delegator, nominationKey);

        Delegation memory delegation = _delegations[delegationKey];
        if (delegation.amount == 0) {
            revert InvalidDelegation(delegatee, delegator, data);
        }
        delete _delegations[delegationKey];
        delete _nominationDelegations[nominationKey][delegation.index];

        Nomination storage nomination = _nominations[nominationKey];
        nomination.delegatedAmount -= delegation.amount;
        nomination.delegations -= 1;

        electionToken.transfer(address(this), delegation.delegator, delegation.amount, true, "0x");
        emit Undelegated(delegatee, delegation.delegator, delegation.amount, data);
    }

    function scheduleElection(uint256 newElectionBlock)
        external
        whenNotPaused
        whenElecting
        nonReentrant
        onlyRole(ELECTIONS_CURATOR_ROLE)
    {
        if (block.number + _MINIMUM_ELECTION_BLOCKS <= newElectionBlock) {
            revert InvalidElectionBlock(newElectionBlock);
        }
        electionBlock = newElectionBlock;
        emit ElectionScheduled(newElectionBlock);
    }

    function recycle(address nominator, bytes calldata data)
        external
        whenNotPaused
        whenElecting
        nonReentrant
        onlyRole(ELECTIONS_CURATOR_ROLE)
    {
        _checkNomination(nominator, data);
        bytes32 nominationKey = _nominatorKey(nominator, data);
        Nomination memory nomination = _nominations[nominationKey];
        if (nomination.blockNumber + _NOMINATION_EXPIRATION_BLOCKS < block.number) {
            revert InvalidNomination(nominator, data);
        }
        delete _nominations[nominationKey];
        emit Recycled(nominator, nomination.amount);
        recycledAmount += nomination.amount;

        for (uint128 i = 0; i < nomination.delegations; i++) {
            bytes32 delegationKey = _nominationDelegations[nominationKey][i];
            Delegation memory delegation = _delegations[delegationKey];
            delete _delegations[delegationKey];
            delete _nominationDelegations[nominationKey][i];

            // try to undelegate, if denied, recycle the delegation
            try electionToken.transfer(address(this), delegation.delegator, delegation.amount, true, "0x") {
                emit Undelegated(nominator, delegation.delegator, delegation.amount, data);
            } catch {
                recycledAmount += delegation.amount;
                emit Recycled(delegation.delegator, delegation.amount);
            }
        }
    }

    function elect(address nominator, bytes calldata data)
        external
        whenNotPaused
        whenElecting
        nonReentrant
        onlyRole(ELECTIONS_CURATOR_ROLE)
    {
        _checkNomination(nominator, data);
        bytes32 nominationKey = _nominatorKey(nominator, data);
        Nomination memory nomination = _nominations[nominationKey];
        delete _nominations[nominationKey];
        emit Recycled(nominator, nomination.amount);

        for (uint128 i = 0; i < nomination.delegations; i++) {
            bytes32 delegationKey = _nominationDelegations[nominationKey][i];
            Delegation memory delegation = _delegations[delegationKey];
            delete _delegations[delegationKey];
            delete _nominationDelegations[nominationKey][i];
            emit Recycled(delegation.delegator, delegation.amount);
        }

        recycledAmount += nomination.amount + nomination.delegatedAmount;
        emit Elected(nominator, nomination.amount, nomination.delegatedAmount, data);
    }
}
