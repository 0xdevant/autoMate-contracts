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
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {AutoMateSetup} from "test/AutoMateSetup.sol";
import {AutoMate} from "src/AutoMate.sol";
import {AutoMateHook} from "src/AutoMateHook.sol";

import "src/interfaces/IAutoMate.sol";

contract TestAutoMateHook is AutoMateSetup {
    function test_swap() public {
    //     deal(alice, 1.01 ether);
    //     deal(bob, 1 ether);
    //     deal(cat, 1 ether);

    //     deal(address(token0), alice, 10000 ether);
    //     vm.prank(alice);
    //     IERC20(address(token0)).approve(address(autoMate), 10000 ether);

    //     console2.log("### BEFORE SUB ###");
    //     console2.log("eth balanceOf(alice):", alice.balance);
    //     console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
    //     vm.prank(alice);
    //     subscribeTaskBy(alice);

    //     console2.log("\n ### AFTER SUB ###");
    //     console2.log("eth balanceOf(alice):", alice.balance);
    //     console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));

    //     console2.log("\n ### BEFORE SWAP ###");
    //     console2.log("eth balanceOf(alice):", alice.balance);
    //     console2.log("eth balanceOf(testing contract):", address(this).balance);
    //     console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
    //     console2.log("token 0 balanceOf(bob):", _normalize(token0.balanceOf(bob)));
    //     console2.log("token 0 balanceOf(cat):", _normalize(token0.balanceOf(cat)));

    //     // Perform a swap and execute task //
    //     vm.warp(block.timestamp + 60);
    //     bool zeroForOne = true;
    //     int256 amountSpecified = -1e18; // negative number indicates exact input swap!
    //     BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    //     // ------------------- //

    //     assertEq(int256(swapDelta.amount0()), amountSpecified);

    //     console2.log("\n ### AFTER SWAP ###");
    //     console2.log("eth balanceOf(alice):", alice.balance);
    //     console2.log("eth balanceOf(testing contract):", address(this).balance);
    //     console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
    //     console2.log("token 0 balanceOf(bob):", _normalize(token0.balanceOf(bob)));
    // }

    // function _normalize(uint256 amount) internal pure returns (uint256) {
    //     return amount / 10 ** 18;
    // }
}
