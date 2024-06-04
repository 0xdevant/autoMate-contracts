// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettleTake} from "v4-core/libraries/CurrencySettleTake.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BaseHook} from "./forks/BaseHook.sol";

import {IAutoMate} from "./interfaces/IAutoMate.sol";

contract AutoMateHook is BaseHook {
    using CurrencySettleTake for Currency;

    uint256 private constant _DUTCH_AUCTION_INTERVAL = 1 hours;
    uint256 private constant _MAX_PRICE_DROP_BP = 200; // 2%

    IAutoMate private _autoMate;

    bool private _isDutchAuctionDisabled;
    uint64 private _lastDutchAuctionStartTs;
    uint8 private _bpDropPerMin = 1; // 0.01% for now, so price drop 0.6% at max

    error OnlyFromAutoMate();

    modifier onlyFromAutoMate() {
        if (msg.sender != address(_autoMate)) revert OnlyFromAutoMate();
        _;
    }

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
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta)
    {
        /**
         * BalanceDelta is a packed value of (currency0Amount, currency1Amount)
         *
         *         BeforeSwapDelta varies such that it is not sorted by token0 and token1
         *         Instead, it is sorted by "specifiedCurrency" and "unspecifiedCurrency"
         *
         *         Specified Currency => The currency in which the user is specifying the amount they're swapping for
         *         Unspecified Currency => The other currency
         *
         *         For example, in an ETH/USDC pool, there are 4 possible swap cases:
         *
         *         1. ETH for USDC with Exact Input for Output (amountSpecified = negative value representing ETH)
         *         2. ETH for USDC with Exact Output for Input (amountSpecified = positive value representing USDC)
         *         3. USDC for ETH with Exact Input for Output (amountSpecified = negative value representing USDC)
         *         4. USDC for ETH with Exact Output for Input (amountSpecified = positive value representing ETH)
         *
         *         In Case (1):
         *             -> the user is specifying their swap amount in terms of ETH, so the specifiedCurrency is ETH
         *             -> the unspecifiedCurrency is USDC
         *
         *         In Case (2):
         *             -> the user is specifying their swap amount in terms of USDC, so the specifiedCurrency is USDC
         *             -> the unspecifiedCurrency is ETH
         *
         *         In Case (3):
         *             -> the user is specifying their swap amount in terms of USDC, so the specifiedCurrency is USDC
         *             -> the unspecifiedCurrency is ETH
         *
         *         In Case (4):
         *             -> the user is specifying their swap amount in terms of ETH, so the specifiedCurrency is ETH
         *             -> the unspecifiedCurrency is USDC
         */
        BeforeSwapDelta beforeSwapDelta = toBeforeSwapDelta(
            int128(-params.amountSpecified), // So `specifiedAmount` = +100
            int128(params.amountSpecified) // Unspecified amount (output delta) = -100
        );

        // use custom price curve with Dutch auction to incentivize keepers to execute the task
        /* AUTOMATE integration STARTS */
        // no change to price curve if Dutch auction is disabled
        if (_isDutchAuctionDisabled) return (this.beforeSwap.selector, beforeSwapDelta);

        // Scenario 1: if has pending task => check if auction already passed 1 hr
        //             => y: start a new auction and reset the price curve n: auction on-going, update new calculation on price curve
        // Scenario 2: if no pending task => back to normal curve

        if (_autoMate.hasPendingTask()) {
            uint256 priceDropBP;

            // auction on-going
            if (block.timestamp < _lastDutchAuctionStartTs + _DUTCH_AUCTION_INTERVAL) {
                // block.timestamp must be > _lastDutchAuctionStartTs at this point
                uint256 minsElapsed = block.timestamp - _lastDutchAuctionStartTs / 1 minutes;
                priceDropBP = _bpDropPerMin * minsElapsed;
            } else {
                // start a new auction & restart the custom price curve Dutch auction
                _lastDutchAuctionStartTs = uint64(block.timestamp);
                priceDropBP = _bpDropPerMin;
            }

            // TODO: call executeTask() with taskId auto assigned since you cannnot pass taskId into beforeSwap()

            // TODO: swap with custom price curve via priceDropBP
            uint256 amountInOutPositive =
                params.amountSpecified > 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified);

            if (params.zeroForOne) {
                // If user is selling Token 0 and buying Token 1

                // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
                // We will take claim tokens for that Token 0 from the PM and keep it in the hook
                // and create an equivalent credit for that Token 0 since it is ours!
                key.currency0.take(poolManager, address(this), amountInOutPositive, true);

                // They will be receiving Token 1 from the PM, creating a credit of Token 1 in the PM
                // We will burn claim tokens for Token 1 from the hook so PM can pay the user
                // and create an equivalent debit for Token 1 since it is ours!
                key.currency1.settle(poolManager, address(this), amountInOutPositive, true);
            } else {
                key.currency0.settle(poolManager, address(this), amountInOutPositive, true);
                key.currency1.take(poolManager, address(this), amountInOutPositive, true);
            }
        } else {
            return (this.beforeSwap.selector, beforeSwapDelta);
        }
        /* AUTOMATE ENDS */

        return (this.beforeSwap.selector, beforeSwapDelta);
    }

    function setBPDropPerMin(uint8 bpDropPerMin) external onlyFromAutoMate {
        _bpDropPerMin = bpDropPerMin;
    }

    function disableDutchAuction() external onlyFromAutoMate {
        _isDutchAuctionDisabled = true;
    }

    function enableDutchAuction() external onlyFromAutoMate {
        _isDutchAuctionDisabled = false;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function isDutchAuctionDisabled() public view returns (bool) {
        return _isDutchAuctionDisabled;
    }
}
