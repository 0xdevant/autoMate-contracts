// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {CurrencySettler} from "v4-core-test/utils/CurrencySettler.sol";

import {BaseHook} from "./forks/BaseHook.sol";
import {IAutoMate} from "./interfaces/IAutoMate.sol";

contract AutoMateHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    uint256 private constant _MAX_PRICE_DROP_BP = 1000; // 10%
    // only allow at most monthly(30 days) task to be scheduled
    uint256 private constant _MAX_DUTCH_AUCTION_INTERVAL_IN_HOUR = 720;
    uint256 private constant _PRICE_DROP_PRECISION = 1e18;
    uint256 private constant _DAILY_IN_HOUR = 24;
    uint256 private constant _WEEKLY_IN_HOUR = 24 * 7;
    uint256 private constant _MONTHLY_IN_HOUR = 24 * 30;
    uint256 private constant _BASIS_POINTS = 10000;

    uint16 public immutable DUTCH_AUCTION_INTERVAL_IN_HOUR;

    /// @dev The interval in hour between each Dutch auction, with different intervals for each pool
    ///      currently only support strict intervals like hourly(1), daily(24), weekly(7*24), monthly(30*24)
    mapping(PoolId poolId => uint16 dutchAuctionIntervalInHour) public poolsDutchAuctionIntervalInHour;

    IAutoMate private _autoMate;

    bool private _isDutchAuctionDisabled;
    uint64 private _lastDutchAuctionStartTs;
    /// @dev The max price drop for Dutch auction in Basis Points relative to dutchAuctionIntervalInHour set for each pool
    ///      for example if dutchAuctionIntervalInHour is 24, _maxBPDropPerDutchAuction is 100:
    ///      there will be 1% max price drop for each daily Dutch auction i.e. 0.0416666667% drop per hour
    uint16 private _maxBPDropPerDutchAuction;

    error OnlyFromAutoMate();
    error ExceedsMaxDutchAuctionInterval();

    modifier onlyFromAutoMate() {
        if (msg.sender != address(_autoMate)) revert OnlyFromAutoMate();
        _;
    }

    constructor(
        IPoolManager poolManager,
        address autoMate,
        uint16 dutchAuctionIntervalInHour,
        uint16 maxBPDropPerDutchAuction
    ) BaseHook(poolManager) {
        if (dutchAuctionIntervalInHour > _MAX_DUTCH_AUCTION_INTERVAL_IN_HOUR) {
            revert ExceedsMaxDutchAuctionInterval();
        }

        _autoMate = IAutoMate(autoMate);
        DUTCH_AUCTION_INTERVAL_IN_HOUR = dutchAuctionIntervalInHour;
        _maxBPDropPerDutchAuction = maxBPDropPerDutchAuction;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
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

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata) external override poolManagerOnly returns (bytes4) {
        poolsDutchAuctionIntervalInHour[key.toId()] = DUTCH_AUCTION_INTERVAL_IN_HOUR;
        return this.afterInitialize.selector;
    }

    // Swapping
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 amountInOutPositive = params.amountSpecified > 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified);

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

        // no change to price curve if Dutch auction is disabled
        if (_isDutchAuctionDisabled) return (this.beforeSwap.selector, beforeSwapDelta, 0);

        uint16 dutchAuctionIntervalInHour = poolsDutchAuctionIntervalInHour[key.toId()];
        uint256 taskCategoryId = _autoMate.getTaskCategoryId(key, _normalizeDutchAuctionInterval(dutchAuctionIntervalInHour));

        // Scenario 1: if has pending task => check if auction already passed 1 hr
        //             => y: start a new auction and reset the price curve / n: auction on-going, update new calculation on price curve
        // Scenario 2: if no pending task => back to normal curve
        if (_autoMate.hasPendingTaskInCategory(taskCategoryId)) {
            // need to divide by _PRICE_DROP_PRECISION in later calculation to get the actual BP
            uint256 currBPDropWithPrecision = _startNewAuctionOrAdjustPriceFactor(
                _lastDutchAuctionStartTs,
                dutchAuctionIntervalInHour,
                _maxBPDropPerDutchAuction
            );

            // swap with custom price curve via * currBPDropWithPrecision / _PRICE_DROP_PRECISION
            beforeSwapDelta = toBeforeSwapDelta(
                _getDiscountedInputAmount(params.amountSpecified, currBPDropWithPrecision),
                int128(params.amountSpecified)
            );

            // executeTask() will be called with an auto assigned taskId since you cannnot pass taskId into beforeSwap()
            _autoMate.executeTask(taskCategoryId, _autoMate.getNextTaskIndex(taskCategoryId));
        } else {
            return (this.beforeSwap.selector, beforeSwapDelta, 0);
        }

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

        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _startNewAuctionOrAdjustPriceFactor(
        uint256 lastDutchAuctionStartTs,
        uint16 dutchAuctionIntervalInHour,
        uint16 maxBPDropPerDutchAuction
    ) internal returns (uint256 currBPDropWithPrecision) {
        // auction on-going
        if (block.timestamp < lastDutchAuctionStartTs + dutchAuctionIntervalInHour * 1 hours) {
            // block.timestamp must be > lastDutchAuctionStartTs at this point
            uint256 hoursElapsed = block.timestamp - lastDutchAuctionStartTs / 1 hours;
            currBPDropWithPrecision = (maxBPDropPerDutchAuction * hoursElapsed * _PRICE_DROP_PRECISION) / dutchAuctionIntervalInHour;
        } else {
            // start a new auction & restart the custom price curve Dutch auction
            _lastDutchAuctionStartTs = uint64(block.timestamp);
            currBPDropWithPrecision = 0;
        }
    }

    function _normalizeDutchAuctionInterval(uint256 dutchAuctionIntervalInHour) internal pure returns (IAutoMate.TaskInterval) {
        if (dutchAuctionIntervalInHour == _DAILY_IN_HOUR) {
            return IAutoMate.TaskInterval.DAILY;
        } else if (dutchAuctionIntervalInHour == _WEEKLY_IN_HOUR) {
            return IAutoMate.TaskInterval.WEEKLY;
        } else if (dutchAuctionIntervalInHour == _MONTHLY_IN_HOUR) {
            return IAutoMate.TaskInterval.MONTHLY;
        }
        return IAutoMate.TaskInterval.HOURLY;
    }

    function _getDiscountedInputAmount(
        int256 amountSpecified,
        uint256 currBPDropWithPrecision
    ) internal pure returns (int128 specifiedDiscountedInputAmount) {
        specifiedDiscountedInputAmount = currBPDropWithPrecision != 0
            ? (int128(-amountSpecified) * (int128(uint128(_BASIS_POINTS)) - int128(uint128(currBPDropWithPrecision)))) /
                int128(uint128(_BASIS_POINTS)) /
                int128(uint128(_PRICE_DROP_PRECISION))
            : int128(-amountSpecified);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    function setBPDropPerMin(uint8 maxBPDropPerDutchAuction) external onlyFromAutoMate {
        _maxBPDropPerDutchAuction = maxBPDropPerDutchAuction;
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

    function getMaxBPDropPerDutchAuction() external view returns (uint16) {
        return _maxBPDropPerDutchAuction;
    }
}
