// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {IPageNameMarketplace, PendingSale} from "../../src/page/IPageNameMarketplace.sol";

contract PageNameMarketplaceMock is IPageNameMarketplace {
    PendingSale private _pendingSale;

    function reset() public {
        delete _pendingSale;
    }

    function setPendingSale(PendingSale calldata pendingSale_) public {
        _pendingSale = pendingSale_;
    }

    function pendingSale() public view returns (PendingSale memory) {
        return _pendingSale;
    }
}
