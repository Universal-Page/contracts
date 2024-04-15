// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {LSP6Utils} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Utils.sol";
import {_PERMISSION_SIGN} from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6Constants.sol";

contract ProfilesReverseLookup {
    error UnathorizedController(address controller, address profile);
    error AlreadyRegistered(address controller, address profile);
    error NotRegistered(address controller, address profile);
    error Unathorized();

    event ProfileRegistered(address indexed controller, address indexed profile, bytes data);
    event ProfileUnregistered(address indexed controller, address indexed profile, bytes data);

    mapping(bytes32 key => uint16 index) private _profileIndices;
    mapping(address controller => address[] profiles) private _profiles;

    function profilesOf(address controller) external view returns (address[] memory) {
        return _profiles[controller];
    }

    function registered(address controller, address profile) external view returns (bool) {
        bytes32 indexKey = _profileIndexKey(controller, profile);
        address[] memory profiles = _profiles[controller];
        return profiles.length > 0 && profiles[_profileIndices[indexKey]] == profile;
    }

    function _profileIndexKey(address controller, address profile) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(controller, profile));
    }

    function register(address controller, address profile, bytes calldata data) external {
        if (msg.sender != controller && msg.sender != profile) {
            revert Unathorized();
        }

        bytes32 permissions = LSP6Utils.getPermissionsFor(IERC725Y(profile), controller);
        bool granted = LSP6Utils.hasPermission(permissions, _PERMISSION_SIGN);
        if (!granted) {
            revert UnathorizedController(controller, profile);
        }

        bytes32 indexKey = _profileIndexKey(controller, profile);
        uint16 index = _profileIndices[indexKey];
        address[] memory profiles = _profiles[controller];

        if (profiles.length > 0 && profiles[index] == profile) {
            revert AlreadyRegistered(controller, profile);
        }

        _profileIndices[indexKey] = uint16(profiles.length);
        _profiles[controller].push(profile);
        emit ProfileRegistered(controller, profile, data);
    }

    function unregister(address controller, address profile, bytes calldata data) external {
        if (msg.sender != controller && msg.sender != profile) {
            revert Unathorized();
        }

        bytes32 indexKey = _profileIndexKey(controller, profile);
        uint16 index = _profileIndices[indexKey];
        address[] memory profiles = _profiles[controller];

        if (profiles.length <= index || profiles[index] != profile) {
            revert NotRegistered(controller, profile);
        }

        uint16 lastIndex = uint16(profiles.length - 1);
        address lastProfile = profiles[lastIndex];

        _profileIndices[_profileIndexKey(controller, lastProfile)] = index;
        _profiles[controller][index] = lastProfile;
        _profiles[controller].pop();
        emit ProfileUnregistered(controller, profile, data);
    }
}
