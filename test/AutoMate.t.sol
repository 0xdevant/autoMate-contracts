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
import {Disperse} from "test/mock/Disperse.sol";

contract TestAutoMate is AutoMateSetup {
    using PoolIdLibrary for PoolKey;

    /*//////////////////////////////////////////////////////////////
                            TASK SUBSCRIPTION
    //////////////////////////////////////////////////////////////*/
    function test_subscribeTask_RevertIfScheduleAtIs0() public userPrank(alice) {
        bytes memory taskInfo = abi.encode(
            defaultBounty,
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(token0),
            address(token0),
            0, // scheduleAt
            1000 ether,
            abi.encodeCall(IERC20.transfer, (bob, 1000 ether))
        );
        IERC20(address(token0)).approve(address(autoMate), 1000 ether);
        vm.expectRevert(IAutoMate.InvalidTaskInput.selector);
        autoMate.subscribeTask{value: defaultBounty + protocolFee}(taskInfo);
    }

    function test_subscribeTask_RevertIfTokenAddressIs0() public userPrank(alice) {
        bytes memory taskInfo = abi.encode(
            defaultBounty,
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(0), // tokenAddress can only be 0 when taskType is NATIVE_TRANSFER or CONTRACT_CALL_WITH_NATIVE
            address(token0),
            uint64(block.timestamp + 1 hours),
            1000 ether,
            abi.encodeCall(IERC20.transfer, (bob, 1000 ether))
        );
        IERC20(address(token0)).approve(address(autoMate), 1000 ether);
        vm.expectRevert(IAutoMate.InvalidTaskInput.selector);
        autoMate.subscribeTask{value: defaultBounty + protocolFee}(taskInfo);
    }

    function test_subscribeTask_RevertIfCallingAddressIs0() public userPrank(alice) {
        bytes memory taskInfo = abi.encode(
            defaultBounty,
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(token0),
            address(0), // callingAddress
            uint64(block.timestamp + 1 hours),
            1000 ether,
            abi.encodeCall(IERC20.transfer, (bob, 1000 ether))
        );
        IERC20(address(token0)).approve(address(autoMate), 1000 ether);
        vm.expectRevert(IAutoMate.InvalidTaskInput.selector);
        autoMate.subscribeTask{value: defaultBounty + protocolFee}(taskInfo);
    }

    function test_subscribeTask_RevertIfJITBountyIs0() public userPrank(alice) {
        bytes memory taskInfo = abi.encode(
            0, // JITBounty
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(token0),
            address(token0),
            uint64(block.timestamp + 1 hours),
            1000 ether,
            abi.encodeCall(IERC20.transfer, (bob, 1000 ether))
        );
        IERC20(address(token0)).approve(address(autoMate), 1000 ether);
        vm.expectRevert(IAutoMate.InvalidTaskInput.selector);
        autoMate.subscribeTask{value: defaultBounty + protocolFee}(taskInfo);
    }

    function test_subscribeTask_RevertIfCallAmountIs0() public userPrank(alice) {
        bytes memory taskInfo = abi.encode(
            defaultBounty,
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(token0),
            address(token0),
            uint64(block.timestamp + 1 hours),
            0, // callAmount
            abi.encodeCall(IERC20.transfer, (bob, 0))
        );
        vm.expectRevert(IAutoMate.InvalidTaskInput.selector);
        autoMate.subscribeTask{value: defaultBounty + protocolFee}(taskInfo);
    }

    function test_subscribeTask_RevertIfCallDataIsEmpty() public userPrank(alice) {
        bytes memory taskInfo = abi.encode(
            defaultBounty,
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(token0),
            address(token0),
            uint64(block.timestamp + 1 hours),
            1000,
            ZERO_BYTES // callData
        );
        vm.expectRevert(IAutoMate.InvalidTaskInput.selector);
        autoMate.subscribeTask{value: defaultBounty + protocolFee}(taskInfo);
    }

    function test_subscribeTask_RevertIfInsufficientFundForProtocolFee() public userPrank(alice) {
        // Bounty = 110 -> Protocol fee = 11 ether (10%)
        // MinRequiredAmount = 121 ether; But Alice has 110 ether only
        uint256 bounty = 110 ether;
        bytes memory taskInfo = abi.encode(
            bounty,
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(token0),
            address(token0),
            uint64(block.timestamp + 1 hours),
            1000,
            abi.encodeCall(IERC20.transfer, (bob, 0))
        );
        IERC20(address(token0)).approve(address(autoMate), 1000 ether);
        vm.expectRevert(IAutoMate.InsufficientSetupFunds.selector);
        autoMate.subscribeTask{value: bounty}(taskInfo);
    }

    /// @notice Detailed walkthrough of how eth/tokens are transferred in subscribeTask
    function test_subscribeTask_CanSubscribeERC20TransferTask() public {
        uint256 scheduledTransferAmount = 1000 ether;

        assertEq(alice.balance, 110 ether);
        assertEq(token0.balanceOf(alice), 10000 ether);
        // Default bounty = 100 ether
        // Protocol fee = 10 ether (10%)
        // Task: Transfer 1000 token0 to Bob, schedule at 1 hour later
        taskId = subscribeERC20TransferTaskBy(alice, scheduledTransferAmount);
        assertEq(taskId, 0);

        // Transferred 100 eth (Bounty) + 10 eth (Protocol fee) => 0 eth remaining
        assertEq(alice.balance, 0);
        // Transferred 1000 units of token0 to AutoMate contract for task execution
        assertEq(token0.balanceOf(alice), 9000 ether);
        assertEq(feeAdmin.balance, 10 ether); // 10% fee of 100 ether

        IAutoMate.Task memory task = autoMate.getTask(taskId);

        assertEq(task.id, taskId);
        assertEq(task.subscriber, alice);
        assertEq(task.jitBounty, defaultBounty);
        assertEq(uint256(task.taskType), uint256(IAutoMate.TaskType.ERC20_TRANSFER));
        assertEq(task.callingAddress, address(token0));
        assertEq(task.scheduleAt, defaultScheduleAt); // 1 hour from now
        assertEq(task.callAmount, scheduledTransferAmount);
        assertEq(task.callData, abi.encodeCall(IERC20.transfer, (bob, scheduledTransferAmount)));
    }

    function test_subscribeTask_CanSubscribeNativeTransferTask() public {
        // Bounty 10 ether -> Protocol fee 1 ether (10%)
        uint256 bounty = 10 ether;
        // Task: Transfer 20 ETH to bob
        uint256 scheduledTransferAmount = 20 ether;

        assertEq(alice.balance, 110 ether);
        taskId = subscribeNativeTransferTaskBy(alice, bounty, scheduledTransferAmount, bob);
        assertEq(feeAdmin.balance, 1 ether); // 10% fee of 10 ether
        assertEq(taskId, 0);
        // 110 - 10 - 1 - 20
        assertEq(alice.balance, 79 ether);
    }

    function test_subscribeTask_CanSubscribeContractCallWithNativeTask() public {
        // Bounty 10 ether -> Protocol fee 1 ether (10%)
        uint256 bounty = 10 ether;
        // Task: Disperse 10, 20, 30 eth to bob, cat, derek respectively
        uint256 scheduledTransferAmount = 60 ether;

        assertEq(alice.balance, 110 ether);
        taskId = subscribeContractCallWithNativeTaskBy(alice, bounty, scheduledTransferAmount);
        assertEq(feeAdmin.balance, 1 ether); // 10% fee of 10 ether
        assertEq(taskId, 0);
        // 110 - 10 - 1 - 60
        assertEq(alice.balance, 39 ether);
    }

    function test_subscribeTask_CanSubscribeContractCallWithERC20Task() public {
        // Bounty 10 ether -> Protocol fee 1 ether (10%)
        uint256 bounty = 10 ether;
        // Task: Disperse 10, 20, 30 ether to bob, cat, derek respectively
        uint256 scheduledTransferAmount = 60 ether;

        assertEq(token0.balanceOf(alice), 10000 ether);

        taskId = subscribeContractCallWithERC20TaskBy(alice, bounty, scheduledTransferAmount);
        assertEq(feeAdmin.balance, 1 ether); // 10% fee of 10 ether
        assertEq(taskId, 0);
        // 110 - 11
        assertEq(alice.balance, 99 ether);
        assertEq(token0.balanceOf(alice), 9940 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            TASK EXECUTION
    //////////////////////////////////////////////////////////////*/
    function test_executeTask_RevertIfNotExecutedFromHook() public {
        taskId = subscribeERC20TransferTaskBy(address(this), 1000 ether);
        vm.expectRevert(IAutoMate.OnlyFromAuthorizedHook.selector);
        autoMate.executeTask("");
    }

    function test_executeTask_RevertIfInvalidReceiverSignature() public {
        taskId = subscribeERC20TransferTaskBy(address(alice), 1000 ether);

        // Swap details
        vm.warp(block.timestamp + 1 hours);
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!

        // hookData: Using bob's private key to sign the claimBounty
        IAutoMate.ClaimBounty memory claimBounty = IAutoMate.ClaimBounty({receiver: cat});
        bytes memory sig = getEIP712Signature(claimBounty, userPrivateKeys[1], autoMate.DOMAIN_SEPARATOR());
        bytes memory encodedHookData = abi.encode(claimBounty, sig);

        vm.startPrank(cat);
        IERC20(address(token0)).approve(address(swapRouter), 1 ether);
        vm.expectRevert(IAutoMate.InvalidReceiverFromHookData.selector);
        swap(key, zeroForOne, amountSpecified, encodedHookData);
        vm.stopPrank();
    }

    /// @notice Detailed walkthrough of how eth/tokens are transferred in executeTask
    function test_executeTask_SwapCanTriggerTaskExecutionAndClaimAllBounty() public {
        // Alice balance before subscription
        assertEq(alice.balance, 110 ether);
        assertEq(token0.balanceOf(alice), 10000 ether);

        // Alice subscribes task with 100 ether JIT Bounty
        // Task: Transfer 1000 token0 to Bob, schedule at 1 hour later
        subscribeERC20TransferTaskBy(alice, 1000 ether);

        // Alice balance after subscription
        // Transfered 100 eth (Bounty) + 10 eth (Protocol fee) + 1000 ether of Token0
        assertEq(alice.balance, 0);
        assertEq(token0.balanceOf(alice), 9000 ether);

        // Balances before someone swaps
        assertEq(cat.balance, 1 ether);
        assertEq(token0.balanceOf(bob), 0);
        assertEq(token0.balanceOf(cat), 10000 ether);

        // Searcher(cat) performs a swap and executes task as at its `scheduledAt`, thus collected the full JIT Bounty
        vm.warp(block.timestamp + 1 hours);
        // swap 1 unit of token0 (Exact input) for token1
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!

        IAutoMate.ClaimBounty memory claimBounty = IAutoMate.ClaimBounty({receiver: cat});
        bytes memory sig = getEIP712Signature(claimBounty, userPrivateKeys[2], autoMate.DOMAIN_SEPARATOR());
        bytes memory encodedHookData = abi.encode(claimBounty, sig);

        approveNecessarySpenders(cat, 10000 ether);
        vm.prank(cat);
        vm.expectEmit(address(autoMate));
        emit IAutoMate.TaskExecuted(cat, 0);
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, encodedHookData);

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

    function test_executeTask_SwapCanTriggerTaskExecutionAndClaimPartOfBounty() public {
        // Alice balance before subscription
        assertEq(alice.balance, 110 ether);
        assertEq(token0.balanceOf(alice), 10000 ether);

        // Alice subscribes task with 100 ether JIT Bounty
        // Transfer 100 ether + 10 ether (Protocol fee)
        // Task: Transfer 1000 token0 to Bob after 1 hour
        subscribeERC20TransferTaskBy(alice, 1000 ether);

        // Searcher(cat) performs a swap and executes task 10 minutes earlier than `scheduleAt`, thus got 10% decay on JIT Bounty
        // swap 1 unit of token0 (Exact input) for token1
        swapToken(cat, block.timestamp + 50 minutes, true, -1e18);

        // 10% JIT amount refunded to subscriber
        assertEq(alice.balance, 10 ether);
        // Cat received 90 ether from the JIT bounty (no decay), 1 + 90 = 91 ether
        assertEq(cat.balance, 91 ether);
        // Bob received 1000 token0 from execution of scheduled task
        assertEq(token0.balanceOf(bob), 1000 ether);
        // Cat's token0 balance reduced by 1 after swap
        assertEq(token0.balanceOf(cat), 9999 ether);
    }

    function test_executeTask_SwapCanTriggerNativeTransferTask() public {
        // Alice subscribes task with 10 ether JIT Bounty
        uint256 bounty = 10 ether;
        // Task: Transfer 20 eth to Bob after 1 hour
        // Transfer 10 eth + 1 eth (Protocol fee) + 20 eth = 31 eth
        uint256 scheduledTransferAmount = 20 ether;
        subscribeNativeTransferTaskBy(alice, bounty, scheduledTransferAmount, bob);

        // Assume swap at `scheduleAt` => taking full JIT bounty for simplicity
        // swap 1 unit of token0 (Exact input) for token1
        swapToken(cat, block.timestamp + 1 hours, true, -1e18);

        // 0 JIT refunded to subscriber, 110 - 31 = 79 eth
        assertEq(alice.balance, 79 ether);
        // Bob received 20 eth from execution of scheduled task, 1 + 20 = 21 ether
        assertEq(bob.balance, 21 ether);
        // Cat received 10 ether from the JIT bounty (no decay), 1 + 10 = 11 ether
        assertEq(cat.balance, 11 ether);
        // Cat's token0 balance reduced by 1 after swap
        assertEq(token0.balanceOf(cat), 9999 ether);
    }

    function test_executeTask_SwapCanTriggerContractCallWithERC20Task() public {
        // Alice subscribes task with 10 ether JIT Bounty
        uint256 bounty = 10 ether;
        // Task: Transfer 10, 20, 30 units of token0 to Bob, Cat and Derek respectively after 1 hour
        // Transfer 10 eth + 1 eth (Protocol fee) + 60 units of token0
        uint256 scheduledTransferAmount = 60 ether;
        subscribeContractCallWithERC20TaskBy(alice, bounty, scheduledTransferAmount);

        // Assume swap at `scheduleAt` => taking full JIT bounty for simplicity
        // swap 1 unit of token0 (Exact input) for token1
        swapToken(cat, block.timestamp + 1 hours, true, -1e18);

        // 0 JIT refunded to subscriber, 110 - 11 = 99 eth
        assertEq(alice.balance, 99 ether);
        // no change on bob's eth balance
        assertEq(bob.balance, 1 ether);
        // Bob received 10 token0 from task
        assertEq(token0.balanceOf(bob), 10 ether);
        // Cat's eth balance + 10 from bounty
        assertEq(cat.balance, 11 ether);
        // Cat's token0 balance 10000 + 20 from task - 1 from swap = 10019
        assertEq(token0.balanceOf(cat), 10019 ether);
        // Derek received 30 units of token0 from task
        assertEq(token0.balanceOf(derek), 30 ether);
    }

    function test_executeTask_SwapCanTriggerContractCallWithNativeTask() public {
        // Alice subscribes task with 10 ether JIT Bounty
        uint256 bounty = 10 ether;
        // Task: Transfer 10, 20, 30 eth to Bob, Cat and Derek respectively after 1 hour
        // Transfer 10 eth + 1 eth (Protocol fee) + 60 eth
        uint256 scheduledTransferAmount = 60 ether;
        subscribeContractCallWithNativeTaskBy(alice, bounty, scheduledTransferAmount);

        // Assume swap at `scheduleAt` => taking full JIT bounty for simplicity
        // swap 1 unit of token0 (Exact input) for token1
        swapToken(cat, block.timestamp + 1 hours, true, -1e18);

        // 0 JIT refunded to subscriber, 110 - 11 - 60 = 39 eth
        assertEq(alice.balance, 39 ether);
        // Bob's eth balance of 1 + received 10 from task
        assertEq(bob.balance, 11 ether);
        // No change on token0's balance
        assertEq(token0.balanceOf(bob), 0);
        // Cat's eth balance of 1 + 10 from bounty + 20 from task = 31
        assertEq(cat.balance, 31 ether);
        // Cat's token0 balance 10000 - 1 from swap
        assertEq(token0.balanceOf(cat), 9999 ether);
        // Derek received 30 eth from task
        assertEq(derek.balance, 30 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    function test_setFeeReceiver_CanSetFeeReceiver() public {
        assertEq(autoMate.getFeeReceiver(), feeAdmin);
        autoMate.setFeeReceiver(alice);
        assertEq(autoMate.getFeeReceiver(), alice);
    }

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
        subscribeERC20TransferTaskBy(address(this), 1000 ether);
        assertTrue(autoMate.hasPendingTask());
    }

    function test_hasActiveTask_ReturnTrueIfThereIsActiveTask() public {
        assertFalse(autoMate.hasActiveTask());
        subscribeERC20TransferTaskBy(address(this), 1000 ether);
        assertTrue(autoMate.hasActiveTask());
    }

    function test_getNumOfTasks_CanGetNumOfTasks() public {
        assertEq(autoMate.getNumOfTasks(), 0);
        subscribeERC20TransferTaskBy(address(this), 1000 ether);
        assertEq(autoMate.getNumOfTasks(), 1);
    }

    function test_getTask_CanGetTaskArrayOfSpecifiedIdAndInterval() public {
        IAutoMate.Task[] memory tasks = autoMate.getTasks();

        // No tasks before subscribing
        assertEq(tasks.length, 0);
        subscribeERC20TransferTaskBy(address(this), defaultTransferAmount);

        tasks = autoMate.getTasks();

        // Should have 1 task after subscribing
        assertEq(tasks.length, 1);
        IAutoMate.Task memory task = tasks[0];
        assertEq(task.id, taskId);
        assertEq(task.subscriber, address(this));
        assertEq(task.jitBounty, defaultBounty);
        assertEq(uint256(task.taskType), uint256(IAutoMate.TaskType.ERC20_TRANSFER));
        assertEq(task.callingAddress, address(token0));
        assertEq(task.scheduleAt, defaultScheduleAt);
        assertEq(task.callAmount, defaultTransferAmount);
        assertEq(task.callData, abi.encodeCall(IERC20.transfer, (bob, defaultTransferAmount)));
    }

    function test_getTask_CanGetTaskDetails() public {
        subscribeERC20TransferTaskBy(address(this), defaultTransferAmount);
        IAutoMate.Task memory task = autoMate.getTask(taskId);

        assertEq(task.id, taskId);
        assertEq(task.subscriber, address(this));
        assertEq(task.jitBounty, defaultBounty);
        assertEq(uint256(task.taskType), uint256(IAutoMate.TaskType.ERC20_TRANSFER));
        assertEq(task.callingAddress, address(token0));
        assertEq(task.scheduleAt, defaultScheduleAt); // 1 hour later
        assertEq(task.callAmount, defaultTransferAmount); // 10000 ether
        assertEq(task.callData, abi.encodeCall(IERC20.transfer, (bob, defaultTransferAmount)));
    }

    function test_getHookAddress_CanGetHookAddress() public view {
        assertEq(autoMate.getHookAddress(), address(autoMateHook));
    }

    function test_getFeeReceiver_CanGetFeeReceiver() public view {
        assertEq(autoMate.getFeeReceiver(), feeAdmin);
    }

    function test_getBountyDecayBPPerMinute_CanGetBountyDecayBPPerMinute() public view {
        assertEq(autoMate.getBountyDecayBPPerMinute(), 100);
    }

    function test_getProtocolFeeBP_CanGetProtocolFeeBP() public view {
        assertEq(autoMate.getProtocolFeeBP(), defaultProtocolFeeBP);
    }
}
