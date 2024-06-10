// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {CurrencySettler} from "v4-core-test/utils/CurrencySettler.sol";

import {BaseHook} from "./forks/BaseHook.sol";
import {IAutoMate} from "./interfaces/IAutoMate.sol";

contract AutoMateHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    IAutoMate private _autoMate;

    constructor(IPoolManager poolManager, address autoMate) BaseHook(poolManager) {
        _autoMate = IAutoMate(autoMate);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true, // Override how swaps are done
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true, // Allow beforeSwap to return a custom delta
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Swapping
    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (hookData.length != 0) {
            // just do normal swap if there is no active task
            if (!_autoMate.hasActiveTask()) return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
            _autoMate.executeTask(hookData);
        }
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
