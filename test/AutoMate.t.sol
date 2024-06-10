// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

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
        assertEq(alice.balance, 1.01 ether);
        taskId = subscribeTaskBy(alice, 1000 ether);
        assertEq(taskId, 0);
        assertEq(alice.balance, 0);
    }

    function test_executeTask_RevertIfNotExecutedFromHook() public {
        taskId = subscribeTaskBy(address(this), 1000 ether);
        vm.expectRevert(IAutoMate.OnlyFromAuthorizedHook.selector);
        autoMate.executeTask("");
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

    function test_setProtocolFeeBP_RevertIfNotOwnerSetProtocolFeeBP() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        autoMate.setProtocolFeeBP(4000);
    }

    function test_setProtocolFeeBP_OwnerCanSetProtocolFeeBP() public {
        assertEq(autoMate.getProtocolFeeBP(), 100);
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
        uint64 scheduleAt = uint64(block.timestamp + 60);

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
        uint64 scheduleAt = uint64(block.timestamp + 60);

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

    function test_getProtocolFeeBP_CanGetProtocolFeeBP() public view {
        assertEq(autoMate.getProtocolFeeBP(), 100);
    }
}
