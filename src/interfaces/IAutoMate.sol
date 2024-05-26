// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAutoMate {
    enum TaskType {
        NATIVE_TRANSFER,
        ERC20_TRANSFER,
        ERC721_TRANSFER,
        ERC1155_TRANSFER,
        CONTRACT_CALL
    }

    struct Task {
        address subscriber;
        address callingContract;
        uint32 intervalInSecs;
        uint40 startTs;
        bool isRecurring;
        uint256 values;
        bytes callData;
    }

    struct TaskInput {
        TaskType taskType;
        uint256 tokenId;
        uint256 totalAmount;
        bytes signature;
    }

    event TaskSubscribed(address indexed subscriber, uint256 taskId);

    error OnlyFromAuthorizedHook();
    error ExceedsMaxInterval();
    error InsufficientFunds();
    error TaskFailed(bytes data);

    function subscribe(Task calldata task, TaskInput calldata taskInput) external payable;
    function triggerTask(uint256 taskId) external;

    function getTaskId(
        address subscriber,
        uint32 intervalInSecs,
        uint40 startTs,
        bool isRecurring,
        uint256 values,
        bytes calldata callData
    ) external pure returns (uint256);
    function getTask(uint256 taskId) external view returns (Task memory);
    function getSubscribersTaskIds(address subscriber) external view returns (uint256[] memory);
    function getProtocolFeeBP() external view returns (uint16);
}
