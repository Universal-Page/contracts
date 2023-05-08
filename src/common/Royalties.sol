// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {IERC725Y} from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";
import {Points} from "./Points.sol";

error InvalidLSP18RoyaltiesPoints(uint32 points);
error InvalidLSP18RoyaltiesData(bytes invalidValue);

bytes32 constant _LSP18_ROYALTIES_RECIPIENTS_KEY = 0xc0569ca6c9180acc2c3590f36330a36ae19015a19f4e85c28a7631e3317e6b9d;
bytes32 constant _LSP18_ROYALTIES_ENFORCE_PAYMENT = 0x580d62ad353782eca17b89e5900e7df3b13b6f4ca9bbc2f8af8bceb0c3d1ecc6;
uint32 constant _LSP18_ROYALTIES_BASIS = Points.BASIS;

struct RoyaltiesInfo {
    bytes4 interfaceId;
    address recipient;
    uint32 points;
}

library Royalties {
    function setRoyalties(address asset, RoyaltiesInfo memory info) internal {
        if (info.points > _LSP18_ROYALTIES_BASIS) {
            revert InvalidLSP18RoyaltiesPoints(info.points);
        }
        bytes memory entriesData = IERC725Y(asset).getData(_LSP18_ROYALTIES_RECIPIENTS_KEY);
        RoyaltiesInfo[] memory entries = _decodeRoyalties(entriesData);

        // find and update existing entry if any
        int256 entryIndex = _indexOfRoyaltiesEntry(entries, info.recipient);

        if (entryIndex < 0) {
            // adding new entry
            entriesData = bytes.concat(entriesData, _encodeRoyaltiesEntry(info));
        } else {
            // updating existing entry
            entries[uint256(entryIndex)] = info;
            entriesData = _encodeRoyalties(entries);
        }

        IERC725Y(asset).setData(_LSP18_ROYALTIES_RECIPIENTS_KEY, entriesData);
    }

    function royalties(address asset) internal view returns (RoyaltiesInfo[] memory) {
        bytes memory value = IERC725Y(asset).getData(_LSP18_ROYALTIES_RECIPIENTS_KEY);
        return _decodeRoyalties(value);
    }

    function royaltiesPaymentEnforced(address asset) internal view returns (bool) {
        bytes memory value = IERC725Y(asset).getData(_LSP18_ROYALTIES_ENFORCE_PAYMENT);
        return value.length > 0 && value[0] != 0;
    }

    function _indexOfRoyaltiesEntry(RoyaltiesInfo[] memory entries, address recipient) private pure returns (int256) {
        uint256 entriesCount = entries.length;
        for (uint256 i = 0; i < entriesCount; i++) {
            RoyaltiesInfo memory entry = entries[i];
            if (entry.recipient == recipient) {
                return int256(i);
            }
        }
        return -1;
    }

    function _decodeRoyalties(bytes memory data) private pure returns (RoyaltiesInfo[] memory) {
        uint256 dataLength = data.length;

        // count number of entries
        uint256 count = 0;
        for (uint256 i = 0; i < dataLength;) {
            uint16 length;
            assembly {
                length := mload(add(add(data, 0x2), i))
            }
            if (length < 4 /* interfaceId */ + 20 /* recipient */ ) {
                revert InvalidLSP18RoyaltiesData(data);
            }
            unchecked {
                i += 2 /* length */ + length;
                count++;
            }
        }

        RoyaltiesInfo[] memory result = new RoyaltiesInfo[](count);
        uint256 k = 0;
        uint256 j = 0;

        while (k < dataLength) {
            uint16 length;
            bytes4 interfaceId;
            address recipient;
            uint32 points;

            assembly {
                length := mload(add(add(data, 0x2), k))
                interfaceId := mload(add(add(data, 0x4), add(k, 2)))
                recipient := div(mload(add(add(data, 0x20), add(k, 6))), 0x1000000000000000000000000)
            }

            // optional points
            if (length >= 4 /* interfaceId */ + 20 /* recipient */ + 4 /* points */ ) {
                assembly {
                    points := mload(add(add(data, 0x4), add(k, 26)))
                }
            }

            // asign entry
            result[j] = RoyaltiesInfo(interfaceId, recipient, points);

            // skip any remaining bytes as unsupported
            unchecked {
                k += 2 /* length */ + length;
                j++;
            }
        }

        return result;
    }

    function _encodeRoyaltiesEntry(RoyaltiesInfo memory entry) private pure returns (bytes memory result) {
        // determine entry length
        uint16 length = 4 /* interfaceId */ + 20; /* recipient */
        if (entry.points > 0) {
            unchecked {
                length += 4; /* points */
            }
        }

        // encode entry
        result = bytes.concat(bytes2(length), entry.interfaceId, bytes20(entry.recipient));

        // optional points
        if (entry.points > 0) {
            result = bytes.concat(result, bytes4(entry.points));
        }
    }

    function _encodeRoyalties(RoyaltiesInfo[] memory entries) private pure returns (bytes memory) {
        bytes memory result = new bytes(0);
        uint256 count = entries.length;
        for (uint256 i = 0; i < count; i++) {
            result = bytes.concat(result, _encodeRoyaltiesEntry(entries[i]));
        }
        return result;
    }
}
