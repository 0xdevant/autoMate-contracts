// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/types/PoolKey.sol";

interface IAutoMate {
    // not support normal contract call for now
    enum TaskType {
        NATIVE_TRANSFER,
        ERC20_TRANSFER,
        CONTRACT_CALL_WITH_NATIVE,
        CONTRACT_CALL_WITH_ERC20
    }

    enum TaskInterval {
        HOURLY,
        DAILY,
        WEEKLY,
        MONTHLY
    }

    /// @param id The ID of the task
    /// @param subscriber The address that subscribed to the task
    /// @param taskType The type of the task
    /// @param taskInterval The interval in between if it's a recurring task
    /// @param lastRunTs The timestamp of the last time the task was executed
    /// @param lastForInHours The duration in hours that the task will last for
    /// @param callingAddress The address that the task will call to
    /// @param totalAmounts The total amount of tokens involved in the task
    /// @param totalValues The total amount of Ethers involved in the task
    /// @param amountForEachRun The amount of tokens/Ethers to be transferred for each run
    /// @param callData The call data to be passed to the callingAddress
    struct Task {
        uint256 id;
        address subscriber;
        TaskType taskType;
        TaskInterval taskInterval;
        uint40 lastRunTs;
        uint40 lastForInHours;
        address callingAddress;
        uint256 totalAmounts;
        uint256 totalValues;
        uint256 amountForEachRun;
        bytes callData;
    }

    event TaskSubscribed(address indexed subscriber, uint256 taskId);

    error OnlyFromAuthorizedHook();
    error ExceedsMaxInterval();
    error InsufficientFunds();
    error TaskFailed(bytes data);
    error InvalidTaskInput();

    function subscribeTask(PoolKey calldata key, bytes calldata taskInfo) external payable returns (uint256 taskId);
    function executeTask(uint256 taskCategoryId, uint256 taskIndex) external payable;

    function getTaskCategoryId(PoolKey calldata key, TaskInterval taskInterval) external pure returns (uint256);
    function hasPendingTaskInCategory(uint256 taskCategoryId) external view returns (bool);
    function getNumOfTasksInCategory(uint256 taskCategoryId) external view returns (uint256);
    function getTasksInCategory(uint256 taskCategoryId) external view returns (Task[] memory);
    function getTask(uint256 taskCategoryId, uint256 taskIndex) external view returns (Task memory);
    function getNextTaskIndex(uint256 taskCategoryId) external view returns (uint256);
    function getProtocolFeeBP() external view returns (uint16);
}
