// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {PoolKey} from "v4-core/types/PoolKey.sol";

interface IDCAHook {
    event DCAOrderPlaced(
        uint256 orderId,
        address user,
        PoolKey key,
        bool zeroForOne,
        uint256 orderAmount,
        uint256 startTs,
        uint16 intervalInDays
    );

    /// @param key The pool key
    /// @param zeroForOne The direction of the swap
    /// @param intervalInDays The interval between each DCA order in days
    struct DCAOrder {
        PoolKey key;
        bool zeroForOne;
        uint16 intervalInDays;
    }

    function getOrderId(PoolKey calldata key, int24 tick, bool zeroForOne, DCAOrder memory dcaOrder)
        public
        pure
        returns (uint256);
}
