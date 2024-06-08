// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {AutoMateHook} from "src/AutoMateHook.sol";
import {AutoMate} from "src/AutoMate.sol";

import "src/interfaces/IAutoMate.sol";

contract AutoMateSetup is Test, Deployers {
    // Use the libraries
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    AutoMate public autoMate;
    AutoMateHook public autoMateHook;

    // Native tokens are represented by address(0)
    Currency ethCurrency = Currency.wrap(address(0));
    MockERC20 token0;
    MockERC20 token1;

    IPoolManager public poolManager;
    address public user = address(1);

    // Variables for AutoMate test cases
    IAutoMate.TaskInterval taskIntervalDaily = IAutoMate.TaskInterval.DAILY;
    uint256 taskId;

    // Variables for AutoMateHook test cases

    function setUp() public {
        // 1) Deploy v4 core contracts (PoolManager, periphery Router contracts for swapping, modifying liquidity etc)
        deployFreshManagerAndRouters();

        // 2) Deploy two test tokens
        (currency0, currency1) = deployMintAndApprove2Currencies();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        // 3) Deploy our AutoMate contract
        // 1% fee
        autoMate = new AutoMate(100);

        // 4) Deploy Hook contract to specified address
        address hookAddress = address(uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        // Daily auction, 1% drop
        deployCodeTo("AutoMateHook.sol", abi.encode(manager, address(autoMate), 24, 100), hookAddress);
        autoMateHook = AutoMateHook(hookAddress);

        // 5) Set the hook address in the AutoMate contract
        autoMate.setHookAddress(address(autoMateHook));

        // 6) Initialize a pool with these two tokens
        (key, ) = initPool(
            currency0,
            currency1,
            autoMateHook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1, // Initial Sqrt(P) value = 1
            ZERO_BYTES // No additional `initData`
        );

        // 7) Add initial liquidity to the pool
        token0.approve(hookAddress, type(uint256).max);
        token1.approve(hookAddress, type(uint256).max);
        token0.approve(address(autoMate), type(uint256).max);
        token1.approve(address(autoMate), type(uint256).max);

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 10 ether, salt: ""}),
            ZERO_BYTES
        );
        // Some liquidity from -120 to +120 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10 ether, salt: ""}),
            ZERO_BYTES
        );
        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: ""
            }),
            ZERO_BYTES
        );
    }

    /*//////////////////////////////////////////////////////////////
                        TEST UTILS
    //////////////////////////////////////////////////////////////*/
    function subscribeTask() public returns (uint256 id) {
        bytes memory taskInfo = abi.encode(
            IAutoMate.TaskType.ERC20_TRANSFER,
            IAutoMate.TaskInterval.DAILY,
            uint40(720),
            address(token0),
            1000 ether,
            0,
            abi.encodeCall(IERC20.transfer, (user, 1 ether))
        );
        id = autoMate.subscribeTask(key, taskInfo);
    }
}
