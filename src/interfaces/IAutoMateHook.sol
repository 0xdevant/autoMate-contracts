// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/types/PoolKey.sol";

interface IAutoMateHook {
    function setBPDropPerMin(uint8 maxBPDropPerDutchAuction) external;
}
