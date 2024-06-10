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
    function test_swapAndExecuteTask_Demo() public {
        vm.startPrank(cat);
        IERC20(address(token0)).approve(address(autoMate), 10000 ether);
        IERC20(address(token0)).approve(address(swapRouter), 10000 ether);
        vm.stopPrank();

        uint256 beforeSubETHBalanceAlice = alice.balance;
        uint256 beforeSubTokenBalanceAlice = token0.balanceOf(alice);
        console2.log("### BEFORE SUBSCRIPTION ###");
        console2.log("eth balanceOf(alice):", beforeSubETHBalanceAlice);
        console2.log("token 0 balanceOf(alice):", _normalize(beforeSubTokenBalanceAlice));
        subscribeTaskBy(alice, defaultTransferAmount);

        uint256 afterSubETHBalanceAlice = alice.balance;
        uint256 afterSubTokenBalanceAlice = token0.balanceOf(alice);
        console2.log("\n ### AFTER SUBSCRIPTION ###");
        console2.log("eth balanceOf(alice):", afterSubETHBalanceAlice);
        console2.log("token 0 balanceOf(alice):", _normalize(afterSubTokenBalanceAlice));

        assertEq(beforeSubETHBalanceAlice - afterSubETHBalanceAlice, defaultBounty + protocolFee);
        assertEq(beforeSubTokenBalanceAlice - afterSubTokenBalanceAlice, defaultTransferAmount);

        uint256 beforeSwapETHBalanceAlice = alice.balance;
        uint256 beforeSwapETHBalanceCat = cat.balance;
        uint256 beforeSwapTokenBalanceBob = token0.balanceOf(bob);

        console2.log("\n ### BEFORE SWAP ###");
        console2.log("eth balanceOf(alice):", beforeSwapETHBalanceAlice);
        console2.log("eth balanceOf(cat):", beforeSwapETHBalanceCat);
        console2.log("token 0 balanceOf(bob):", _normalize(beforeSwapTokenBalanceBob));

        // Searcher(cat) performs a swap and executes task 1 min earlier, results in 1% bounty decay //
        vm.warp(block.timestamp);
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!

        IAutoMate.ClaimBounty memory claimBounty = IAutoMate.ClaimBounty({receiver: cat});
        bytes memory sig = getEIP712Signature(claimBounty, userPrivateKeys[2], autoMate.DOMAIN_SEPARATOR());
        bytes memory encodedHookData = abi.encode(claimBounty, sig);

        vm.prank(cat);
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, encodedHookData);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        uint256 afterSwapETHBalanceAlice = alice.balance;
        uint256 afterSwapETHBalanceCat = cat.balance;
        uint256 afterSwapTokenBalanceBob = token0.balanceOf(bob);

        console2.log("\n ### AFTER SWAP ###");
        console2.log("eth balanceOf(alice):", afterSwapETHBalanceAlice);
        console2.log("eth balanceOf(cat):", afterSwapETHBalanceCat);
        console2.log("token 0 balanceOf(bob):", _normalize(afterSwapTokenBalanceBob));

        (uint256 remainingBountyAmount, uint256 decayAmount) = calculateRemainingBountyByMin(1);
        assertEq(afterSwapETHBalanceAlice - beforeSwapETHBalanceAlice, decayAmount);
        assertEq(afterSwapETHBalanceCat - beforeSwapETHBalanceCat, remainingBountyAmount);
        assertEq(afterSwapTokenBalanceBob - beforeSwapTokenBalanceBob, defaultTransferAmount);
    }

    function test_beforeSwap_TaskExecutedBeforeSwap() public {
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

        IAutoMate.ClaimBounty memory claimBounty = IAutoMate.ClaimBounty({receiver: cat});
        bytes memory sig = getEIP712Signature(claimBounty, userPrivateKeys[2], autoMate.DOMAIN_SEPARATOR());
        bytes memory encodedHookData = abi.encode(claimBounty, sig);

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
