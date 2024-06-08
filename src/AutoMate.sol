// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {IAutoMate} from "./interfaces/IAutoMate.sol";

contract AutoMate is Ownable, IAutoMate {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    uint256 constant BASIS_POINTS = 10000;

    mapping(uint256 taskCategoryId => Task[]) private _tasks;
    /// @dev This is to keep track of the next task to be executed in the category since all recurring tasks are still stored in the array
    mapping(uint256 taskCategoryId => uint256 taskPtr) private _taskPtrs;

    uint256 private _taskIdCounter;

    address private _hookAddress;
    uint16 private _protocolFeeBP;

    modifier onlyFromHook() {
        if (msg.sender != _hookAddress) {
            revert OnlyFromAuthorizedHook();
        }
        _;
    }

    constructor(uint16 protocolFeeBP) Ownable(msg.sender) {
        protocolFeeBP = protocolFeeBP;
    }

    function subscribeTask(PoolKey calldata key, bytes calldata taskInfo) external payable returns (uint256 taskId) {
        (
            TaskType taskType,
            TaskInterval taskInterval,
            uint40 lastForInHours,
            address callingAddress,
            uint256 totalAmounts,
            uint256 totalValues,
            bytes memory callData
        ) = abi.decode(taskInfo, (TaskType, TaskInterval, uint40, address, uint256, uint256, bytes));

        _sanityCheck(lastForInHours, callingAddress, totalAmounts, totalValues);

        // TODO: make use of Oracle to take protocol fee in USD term from totalAmounts / totalValues, to compensate for the custom price curve

        uint256 amountForEachRun = _setupForTask(taskType, lastForInHours, callingAddress, totalAmounts, totalValues);

        uint256 taskCategoryId = getTaskCategoryId(key, taskInterval);
        taskId = _taskIdCounter++; // starts at 0
        Task memory task = Task(
            taskId,
            msg.sender,
            taskType,
            taskInterval,
            0, // lastRunTs
            lastForInHours,
            callingAddress,
            totalAmounts,
            totalValues,
            amountForEachRun,
            callData
        );
        _tasks[taskCategoryId].push(task);

        emit TaskSubscribed(msg.sender, taskId);
    }

    /// @dev the execution time won't be exact, with at max 1 hour delay depends on how the Dutch auction goes
    function executeTask(uint256 taskCategoryId, uint256 currentTaskPtr) external payable onlyFromHook {
        Task[] memory tasksInCategory = _tasks[taskCategoryId];
        Task memory task = tasksInCategory[currentTaskPtr];

        task.lastRunTs = uint40(block.timestamp);
        task.lastForInHours -= _convertIntervalToHr(task.taskInterval);
        // move to next task since current task is still recurring, if it's pointing to last task then reset to 0
        _taskPtrs[taskCategoryId] = currentTaskPtr + 1 == tasksInCategory.length ? 0 : currentTaskPtr + 1;

        // remove the task if it's the last run
        if (task.lastForInHours == 0) {
            tasksInCategory[currentTaskPtr] = _tasks[taskCategoryId][tasksInCategory.length - 1];
            _tasks[taskCategoryId].pop();
            // NB: this means ptr will be pointed to the most recently subscribed task i.e. the newest task becomes next task to be executed
            // there can be an improvement since this makes the older task execution not "very time-sensitive" as newer subscription could be reorderred to the front
            _taskPtrs[taskCategoryId] = currentTaskPtr;
        }

        _executeTaskBasedOnTaskType(task);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _sanityCheck(uint40 lastForInHours, address callingAddress, uint256 totalAmounts, uint256 totalValues) internal pure {
        if (
            lastForInHours == 0 ||
            callingAddress == address(0) ||
            (totalAmounts == 0 && totalValues == 0) ||
            (totalAmounts != 0 && totalValues != 0)
        ) {
            revert InvalidTaskInput();
        }
    }

    /// @dev setup all the prerequisites in order for the scheduled task to execute successfully
    function _setupForTask(
        TaskType taskType,
        uint40 lastForInHours,
        address callingAddress,
        uint256 totalAmounts,
        uint256 totalValues
    ) internal returns (uint256 amountForEachRun) {
        if (taskType == TaskType.NATIVE_TRANSFER || taskType == TaskType.CONTRACT_CALL_WITH_NATIVE) {
            if (msg.value < totalValues) {
                revert InsufficientFunds();
            }
            amountForEachRun = totalValues / lastForInHours;
        }
        if (taskType == TaskType.ERC20_TRANSFER || taskType == TaskType.CONTRACT_CALL_WITH_ERC20) {
            IERC20(callingAddress).safeTransferFrom(msg.sender, address(this), totalAmounts);
            amountForEachRun = totalAmounts / lastForInHours;
        }
    }

    function _convertIntervalToHr(TaskInterval taskInterval) internal pure returns (uint40 hour) {
        if (taskInterval == TaskInterval.HOURLY) {
            return 1;
        } else if (taskInterval == TaskInterval.DAILY) {
            return 24;
        } else if (taskInterval == TaskInterval.WEEKLY) {
            return 24 * 7;
        } else if (taskInterval == TaskInterval.MONTHLY) {
            return 24 * 30;
        }
    }

    function _executeTaskBasedOnTaskType(Task memory task) internal {
        if (task.taskType == TaskType.NATIVE_TRANSFER) {
            payable(task.callingAddress).transfer(task.amountForEachRun);
        }
        if (task.taskType == TaskType.ERC20_TRANSFER) {
            IERC20(task.callingAddress).safeTransfer(task.callingAddress, task.amountForEachRun);
        }
        if (task.taskType == TaskType.CONTRACT_CALL_WITH_NATIVE) {
            (bool success, bytes memory data) = payable(task.callingAddress).call{value: task.amountForEachRun}(task.callData);
            if (!success) revert TaskFailed(data);
        }
        if (task.taskType == TaskType.CONTRACT_CALL_WITH_ERC20) {
            (bool success, bytes memory data) = task.callingAddress.call(task.callData);
            if (!success) revert TaskFailed(data);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    function setHookAddress(address hookAddress) external onlyOwner {
        _hookAddress = hookAddress;
    }

    function setProtocolFeeBP(uint16 protocolFeeBP) external onlyOwner {
        _protocolFeeBP = protocolFeeBP;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function getTaskCategoryId(PoolKey calldata key, TaskInterval taskInterval) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(key.toId(), taskInterval)));
    }

    function hasPendingTaskInCategory(uint256 taskCategoryId) external view returns (bool) {
        return _tasks[taskCategoryId].length > 0;
    }

    function getNumOfTasksInCategory(uint256 taskCategoryId) external view returns (uint256) {
        return _tasks[taskCategoryId].length;
    }

    function getTasksInCategory(uint256 taskCategoryId) external view returns (Task[] memory) {
        return _tasks[taskCategoryId];
    }

    function getTask(uint256 taskCategoryId, uint256 taskIndex) external view returns (Task memory) {
        return _tasks[taskCategoryId][taskIndex];
    }

    function getNextTaskIndex(uint256 taskCategoryId) external view returns (uint256) {
        return _taskPtrs[taskCategoryId];
    }

    function getProtocolFeeBP() external view returns (uint16) {
        return _protocolFeeBP;
    }
}
