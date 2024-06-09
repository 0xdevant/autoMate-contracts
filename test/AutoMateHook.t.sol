// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import {AutoMateSetup} from "test/AutoMateSetup.sol";
import {AutoMate} from "src/AutoMate.sol";

import "src/interfaces/IAutoMate.sol";

contract TestAutoMateHook is AutoMateSetup {
    function test_BeforeSwap_TaskExecutedBeforeSwap() public {
        vm.startPrank(cat);
        IERC20(address(token0)).approve(address(autoMate), 10000 ether);
        IERC20(address(token0)).approve(address(swapRouter), 10000 ether);
        vm.stopPrank();

        console2.log("### BEFORE SUB ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
        subscribeTaskBy(alice, 1000 ether);

        console2.log("\n ### AFTER SUB ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));

        console2.log("\n ### BEFORE SWAP ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("eth balanceOf(cat):", cat.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
        console2.log("token 0 balanceOf(bob):", _normalize(token0.balanceOf(bob)));
        console2.log("token 0 balanceOf(cat):", _normalize(token0.balanceOf(cat)));

        // Perform a swap and execute task //
        vm.warp(block.timestamp);
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!

        IAutoMate.Swapper memory swapper = IAutoMate.Swapper({executor: cat});
        bytes memory sig = getPermitSignature(swapper, userPrivateKeys[2], autoMate.DOMAIN_SEPARATOR());
        bytes memory encodedHookData = abi.encode(swapper, sig);

        vm.prank(cat);
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, encodedHookData);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        console2.log("\n ### AFTER SWAP ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("eth balanceOf(cat):", cat.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
        console2.log("token 0 balanceOf(bob):", _normalize(token0.balanceOf(bob)));
        console2.log("token 0 balanceOf(cat):", _normalize(token0.balanceOf(cat)));
    }
}
