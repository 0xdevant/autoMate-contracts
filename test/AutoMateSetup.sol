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

// Our contracts
import {HookMiner} from "test/utils/HookMiner.sol";
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
    PoolKey public poolKey;
    address public user = address(1);

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

        // 4) Mine an address that has flags set for the hook functions we want
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(AutoMateHook).creationCode,
            abi.encode(poolManager, address(autoMate), 24, 100)
        );

        // 5) Deploy our hook
        // Daily auction, 1% drop
        autoMateHook = new AutoMateHook{salt: salt}(
            poolManager,
            address(autoMate),
            24,
            100
        );

        // 6) Set the hook address in the AutoMate contract
        autoMate.setHookAddress(address(autoMateHook));

        // 7) Initialize a pool with these two tokens
        (poolKey, ) = initPool(
            currency0,
            currency1,
            autoMateHook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1, // Initial Sqrt(P) value = 1
            ZERO_BYTES // No additional `initData`
        );

        // Approve AutoMate contract to spend tokens
        token0.approve(address(autoMate), type(uint256).max);
        token1.approve(address(autoMate), type(uint256).max);
    }
}
