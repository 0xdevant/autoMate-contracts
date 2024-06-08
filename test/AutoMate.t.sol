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
        taskId = subscribeTask();
        assertEq(taskId, 0);
    }

    function test_executeTask_RevertIfNotExecutedFromHook() public {
        taskId = subscribeTask();
        uint256 taskCategoryId = autoMate.getTaskCategoryId(key, taskIntervalDaily);
        vm.expectRevert(IAutoMate.OnlyFromAuthorizedHook.selector);
        autoMate.executeTask(taskCategoryId, 0);
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
    function test_getTaskCategoryId_CanReturnTaskCategroyId() public {
        subscribeTask();
        uint256 taskCategoryId = uint256(keccak256(abi.encode(key.toId(), taskIntervalDaily)));
        assertEq(autoMate.getTaskCategoryId(key, taskIntervalDaily), taskCategoryId);
    }

    function test_hasPendingTaskInCategory_ReturnTrueIfThereIsPendingTask() public {
        uint256 taskCategoryId = autoMate.getTaskCategoryId(key, taskIntervalDaily);
        assertFalse(autoMate.hasPendingTaskInCategory(taskCategoryId));
        subscribeTask();
        assertTrue(autoMate.hasPendingTaskInCategory(taskCategoryId));
    }

    function test_getNumOfTasksInCategory_CanGetNumOfTasks() public {
        uint256 taskCategoryId = autoMate.getTaskCategoryId(key, taskIntervalDaily);
        assertEq(autoMate.getNumOfTasksInCategory(taskCategoryId), 0);
        subscribeTask();
        assertEq(autoMate.getNumOfTasksInCategory(taskCategoryId), 1);
    }

    function test_getTaskInCategory_CanGetTaskArrayOfSpecifiedIdAndInterval() public {
        uint256 taskCategoryId = autoMate.getTaskCategoryId(key, taskIntervalDaily);
        IAutoMate.Task[] memory tasks = autoMate.getTasksInCategory(taskCategoryId);

        // No tasks before subscribing
        assertEq(tasks.length, 0);
        subscribeTask();

        uint256 lastForInHours = 720;
        uint256 totalAmounts = 1000 ether;
        uint256 amountForEachRun = totalAmounts / lastForInHours;

        tasks = autoMate.getTasksInCategory(taskCategoryId);

        // Should have 1 task after subscribing
        assertEq(tasks.length, 1);
        IAutoMate.Task memory task = tasks[0];
        assertEq(task.id, taskId);
        assertEq(task.subscriber, address(this));
        assertEq(uint256(task.taskType), uint256(IAutoMate.TaskType.ERC20_TRANSFER));
        assertEq(uint256(task.taskInterval), uint256(taskIntervalDaily));
        assertEq(task.lastRunTs, 0);
        assertEq(task.lastForInHours, lastForInHours);
        assertEq(task.callingAddress, address(token0));
        assertEq(task.totalAmounts, totalAmounts);
        assertEq(task.totalValues, 0);
        assertEq(task.amountForEachRun, amountForEachRun);
        assertEq(task.callData, abi.encodeCall(IERC20.transfer, (user, 1 ether)));
    }

    function test_getTask_CanGetTaskDetails() public {
        uint256 taskCategoryId = autoMate.getTaskCategoryId(key, taskIntervalDaily);

        subscribeTask();
        IAutoMate.Task memory task = autoMate.getTask(taskCategoryId, taskId);
        uint256 lastForInHours = 720;
        uint256 totalAmounts = 1000 ether;
        uint256 amountForEachRun = totalAmounts / lastForInHours;

        assertEq(task.id, taskId);
        assertEq(task.subscriber, address(this));
        assertEq(uint256(task.taskType), uint256(IAutoMate.TaskType.ERC20_TRANSFER));
        assertEq(uint256(task.taskInterval), uint256(taskIntervalDaily));
        assertEq(task.lastRunTs, 0);
        assertEq(task.lastForInHours, lastForInHours);
        assertEq(task.callingAddress, address(token0));
        assertEq(task.totalAmounts, totalAmounts);
        assertEq(task.totalValues, 0);
        assertEq(task.amountForEachRun, amountForEachRun);
        assertEq(task.callData, abi.encodeCall(IERC20.transfer, (user, 1 ether)));
    }

    function test_getNextTaskIndex_CanGetNextTaskIndex() public {
        uint256 taskCategoryId = autoMate.getTaskCategoryId(key, taskIntervalDaily);
        assertEq(autoMate.getNextTaskIndex(taskCategoryId), 0);
        subscribeTask();
        assertEq(autoMate.getNextTaskIndex(taskCategoryId), 0);
        // execute task logic for next task index
    }

    function test_getHookAddress_CanGetHookAddress() public view {
        assertEq(autoMate.getHookAddress(), address(autoMateHook));
    }

    function test_getProtocolFeeBP_CanGetProtocolFeeBP() public view {
        assertEq(autoMate.getProtocolFeeBP(), 100);
    }
}
