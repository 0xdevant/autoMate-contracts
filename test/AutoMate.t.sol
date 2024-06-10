// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

// Our Contracts
import {AutoMateSetup} from "test/AutoMateSetup.sol";
import {AutoMate} from "src/AutoMate.sol";
import {AutoMateHook} from "src/AutoMateHook.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAutoMate} from "src/interfaces/IAutoMate.sol";

contract TestAutoMate is AutoMateSetup {
    using PoolIdLibrary for PoolKey;

    /*//////////////////////////////////////////////////////////////
                            TASKS RELATED
    //////////////////////////////////////////////////////////////*/
    function test_subscribeTask_CanSubscribeTask() public {
        taskId = subscribeTaskBy(alice, 1000 ether);
        assertEq(taskId, 0);
        assertEq(alice.balance, 0);
    }

    function test_executeTask_RevertIfNotExecutedFromHook() public {
        taskId = subscribeTaskBy(address(this), 1000 ether);
        vm.expectRevert(IAutoMate.OnlyFromAuthorizedHook.selector);
        autoMate.executeTask("");
    }

    function test_executeTask_SwapCanTriggerTaskExecutionAndDistributeJITBounty() public {
        // Alice balance before subscription
        assertEq(alice.balance, 110 ether);
        assertEq(token0.balanceOf(alice), 10000 ether);

        // Alice subscribes task with 1 ether JIT Bounty
        // Transfer 1 ether + 0.01 ether (Protocol fee)
        // Task: Transfer 1000 token0 to Bob after 1 minute
        subscribeTaskBy(alice, 1000 ether);

        // Alice balance after subscription
        assertEq(alice.balance, 0);
        assertEq(token0.balanceOf(alice), 9000 ether);

        // Balances before someone swaps
        assertEq(cat.balance, 1 ether);
        assertEq(token0.balanceOf(bob), 0);
        assertEq(token0.balanceOf(cat), 10000 ether);

        // Searcher(cat) performs a swap and executes as at its `scheduledAt`, thus collected the full JIT Bounty
        vm.warp(block.timestamp + 1 hours);
        // swap 1 unit of token0 (Exact input) for token1
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!

        IAutoMate.ClaimBounty memory claimBounty = IAutoMate.ClaimBounty({receiver: cat});
        bytes memory sig = getEIP712Signature(claimBounty, userPrivateKeys[2], autoMate.DOMAIN_SEPARATOR());
        bytes memory encodedHookData = abi.encode(claimBounty, sig);

        approveNecessarySpenders(cat, 10000 ether);
        vm.prank(cat);
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, encodedHookData);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        // No JIT amount refunded to subscriber
        assertEq(alice.balance, 0);
        // Cat received 100 ether from the JIT bounty (no decay), 1 + 100 = 101 ether
        assertEq(cat.balance, 101 ether);
        // Bob received 1000 token0 from execution of scheduled task
        assertEq(token0.balanceOf(bob), 1000 ether);
        // Cat's token0 balance reduced by 1 after swap
        assertEq(token0.balanceOf(cat), 9999 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    function test_setHookAddress_RevertIfNotOwnerSetHookAddress() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        autoMate.setHookAddress(address(autoMateHook));
    }

    function test_setHookAddress_OwnerCanSetHookAddress() public {
        autoMate.setHookAddress(address(1));
        assertEq(autoMate.getHookAddress(), address(1));
    }

    function test_setBountyDecayBPPerMinute_RevertIfNotOwnerSetBountyDecayBPPerMinute() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        autoMate.setBountyDecayBPPerMinute(1000);
    }

    function test_setBountyDecayBPPerMinute_RevertIfDecayBPIsLargerThan10000() public {
        vm.expectRevert(IAutoMate.InvalidBountyDecayBPPerMinute.selector);
        autoMate.setBountyDecayBPPerMinute(10001);
    }

    function test_setBountyDecayBPPerMinute_OwnerCanSetBountyDecayBPPerMinute() public {
        assertEq(autoMate.getBountyDecayBPPerMinute(), 100);
        autoMate.setBountyDecayBPPerMinute(1000);
        assertEq(autoMate.getBountyDecayBPPerMinute(), 1000);
    }

    function test_setProtocolFeeBP_RevertIfNotOwnerSetProtocolFeeBP() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        autoMate.setProtocolFeeBP(4000);
    }

    function test_setProtocolFeeBP_OwnerCanSetProtocolFeeBP() public {
        assertEq(autoMate.getProtocolFeeBP(), defaultProtocolFeeBP);
        autoMate.setProtocolFeeBP(4000);
        assertEq(autoMate.getProtocolFeeBP(), 4000);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function test_hasPendingTask_ReturnTrueIfThereIsPendingTask() public {
        assertFalse(autoMate.hasPendingTask());
        subscribeTaskBy(address(this), 1000 ether);
        assertTrue(autoMate.hasPendingTask());
    }

    function test_getNumOfTasks_CanGetNumOfTasks() public {
        assertEq(autoMate.getNumOfTasks(), 0);
        subscribeTaskBy(address(this), 1000 ether);
        assertEq(autoMate.getNumOfTasks(), 1);
    }

    function test_getTask_CanGetTaskArrayOfSpecifiedIdAndInterval() public {
        IAutoMate.Task[] memory tasks = autoMate.getTasks();

        // No tasks before subscribing
        assertEq(tasks.length, 0);
        subscribeTaskBy(address(this), defaultTransferAmount);

        uint256 callAmount = defaultTransferAmount;
        uint64 scheduleAt = defaultScheduleAt;

        tasks = autoMate.getTasks();

        // Should have 1 task after subscribing
        assertEq(tasks.length, 1);
        IAutoMate.Task memory task = tasks[0];
        assertEq(task.id, taskId);
        assertEq(task.subscriber, address(this));
        assertEq(task.jitBounty, defaultBounty);
        assertEq(uint256(task.taskType), uint256(IAutoMate.TaskType.ERC20_TRANSFER));
        assertEq(task.callingAddress, address(token0));
        assertEq(task.scheduleAt, scheduleAt);
        assertEq(task.callAmount, callAmount);
        assertEq(task.callData, abi.encodeCall(IERC20.transfer, (bob, defaultTransferAmount)));
    }

    function test_getTask_CanGetTaskDetails() public {
        subscribeTaskBy(address(this), defaultTransferAmount);
        IAutoMate.Task memory task = autoMate.getTask(taskId);
        uint256 callAmount = defaultTransferAmount;
        uint64 scheduleAt = defaultScheduleAt;

        assertEq(task.id, taskId);
        assertEq(task.subscriber, address(this));
        assertEq(task.jitBounty, defaultBounty);
        assertEq(uint256(task.taskType), uint256(IAutoMate.TaskType.ERC20_TRANSFER));
        assertEq(task.callingAddress, address(token0));
        assertEq(task.scheduleAt, scheduleAt);
        assertEq(task.callAmount, callAmount);
        assertEq(task.callData, abi.encodeCall(IERC20.transfer, (bob, defaultTransferAmount)));
    }

    function test_getHookAddress_CanGetHookAddress() public view {
        assertEq(autoMate.getHookAddress(), address(autoMateHook));
    }

    function test_getBountyDecayBPPerMinute_CanGetBountyDecayBPPerMinute() public view {
        assertEq(autoMate.getBountyDecayBPPerMinute(), 100);
    }

    function test_getProtocolFeeBP_CanGetProtocolFeeBP() public view {
        assertEq(autoMate.getProtocolFeeBP(), defaultProtocolFeeBP);
    }
}
