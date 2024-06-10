// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAutoMate {
    // not support plain contract call for now
    enum TaskType {
        NATIVE_TRANSFER,
        ERC20_TRANSFER,
        CONTRACT_CALL_WITH_NATIVE,
        CONTRACT_CALL_WITH_ERC20
    }

    /// @param id The ID of the task
    /// @param subscriber The address that subscribed to the task
    /// @param jitBounty The max amount of Ethers to be paid to the executor if the task is executed JIT
    /// @param taskType The type of the task
    /// @param callingAddress The address that the task will call to
    /// @param scheduleAt The timestamp of the time the task need to be executed, executor will be able to claim the max bounty if the task is executed just in time(JIT)
    /// @param callAmount The amount of tokens/Ethers involved in the task
    /// @param callData The call data to be passed to the callingAddress
    struct Task {
        uint256 id;
        address subscriber;
        uint256 jitBounty;
        TaskType taskType;
        address callingAddress;
        uint64 scheduleAt;
        uint256 callAmount;
        bytes callData;
    }

    // used to verify the receiver of the bounty via EIP712 compatible signature
    struct ClaimBounty {
        address receiver;
    }

    event TaskSubscribed(address indexed subscriber, uint256 taskId);
    event TaskExecuted(address indexed executor, uint256 taskId);

    error OnlyFromAuthorizedHook();
    error OnlyFromTaskSubscriber();
    error InsufficientSetupFunds();
    error InsufficientTaskFunds();
    error TaskFailed(bytes data);
    error InvalidTaskInput();
    error InvalidProtocolFeeBP();
    error InvalidBountyDecayBPPerMinute();
    error InvalidReceiverFromHookData();
    error AllTasksExpired();
    error TaskNotExpiredYet();

    function subscribeTask(bytes calldata taskInfo) external payable returns (uint256 taskId);
    function executeTask(bytes calldata hookData) external payable;

    function hasPendingTask() external view returns (bool);
    function hasActiveTask() external view returns (bool);
    function getNumOfTasks() external view returns (uint256);
    function getTask(uint256 taskIndex) external view returns (Task memory);
    function getHookAddress() external view returns (address);
    function getProtocolFeeBP() external view returns (uint16);
}
