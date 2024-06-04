// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAutoMate {
    enum TaskType {
        NATIVE_TRANSFER,
        ERC20_TRANSFER,
        CONTRACT_CALL
    }

    // if intervalInHours == lastForInHours, then it's a one-time task
    struct Task {
        uint256 id;
        address subscriber;
        TaskType taskType;
        address callingContract;
        uint40 lastRunTs;
        uint16 intervalInHours;
        uint16 lastForInHours;
        uint256 totalAmounts;
        uint256 totalValues;
        bytes callData;
    }

    event TaskSubscribed(address indexed subscriber, uint256 taskId);

    error OnlyFromAuthorizedHook();
    error ExceedsMaxInterval();
    error InsufficientFunds();
    error TaskFailed(bytes data);

    function subscribeTask(bytes memory taskInfo) external payable returns (uint256 taskId);
    function executeTask(uint256 taskId) external;

    function hasPendingTask() external view returns (bool);
    function getTask(uint256 taskId) external view returns (Task memory);
    function getProtocolFeeBP() external view returns (uint16);
}
