// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {AutoMateEIP712} from "./AutoMateEIP712.sol";
import {IAutoMate} from "./interfaces/IAutoMate.sol";

contract AutoMate is Ownable, AutoMateEIP712, IAutoMate {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    bytes32 private constant _CLAIM_BOUNTY_TYPEHASH = keccak256("ClaimBounty(address receiver)");
    uint256 private constant _BASIS_POINTS = 10000;
    // uint256 private constant _MIN_ERC20_BOUNTY = 1e18;

    Task[] private _tasks;
    /// @dev This is to save gas from needing to loop through expired tasks to get the next active task index, since there could be expired tasks still being stored in the array
    uint256 private _activeTaskStartingIdx;

    uint256 private _taskIdCounter;

    address private _hookAddress;
    uint16 private _protocolFeeBP;
    /// @dev 1% decay on jitBounty per minute based on how close the execution time is to the scheduled time
    uint16 private _bountyDecayBPPerMinute;

    modifier onlyFromHook() {
        if (msg.sender != _hookAddress) {
            revert OnlyFromAuthorizedHook();
        }
        _;
    }

    constructor(uint16 protocolFeeBP, uint16 bountyDecayBPPerMinute)
        Ownable(msg.sender)
        AutoMateEIP712("AutoMate", "1")
    {
        _protocolFeeBP = protocolFeeBP;
        _bountyDecayBPPerMinute = bountyDecayBPPerMinute;
    }

    function subscribeTask(bytes calldata taskInfo) external payable returns (uint256 taskId) {
        (
            uint256 jitBounty,
            TaskType taskType,
            address tokenAddress,
            address callingAddress,
            uint64 scheduleAt,
            uint256 callAmount,
            bytes memory callData
        ) = abi.decode(taskInfo, (uint256, TaskType, address, address, uint64, uint256, bytes));

        _sanityCheck(scheduleAt, tokenAddress, callingAddress, jitBounty, callAmount, taskType, callData);
        _setupForTask(taskType, tokenAddress, jitBounty, callAmount);

        taskId = _taskIdCounter++; // starts at 0
        Task memory task = Task(
            taskId, msg.sender, jitBounty, taskType, tokenAddress, callingAddress, scheduleAt, callAmount, callData
        );
        _tasks.push(task);

        emit TaskSubscribed(msg.sender, taskId);
    }

    /// @dev execute task based on the index found on task that can be executed closest to its scheduleAt(JIT)
    function executeTask(bytes calldata hookData) external payable onlyFromHook {
        // verify the receiver is indeed owned by the executor address via signature passed through hook data
        (ClaimBounty memory claimBounty, bytes memory sig) = abi.decode(hookData, (ClaimBounty, bytes));

        (uint256 closestToJITIdx, uint256 activeStartingIdx) = _tryGetClosestToJITIdx(_activeTaskStartingIdx);
        Task memory task = _tasks[closestToJITIdx];

        _tasks[closestToJITIdx] = _tasks[_tasks.length - 1];
        _tasks.pop();
        // save gas to skip the loop to filter expired tasks
        _activeTaskStartingIdx = activeStartingIdx;

        // task still accessible after pop
        _executeTaskBasedOnTaskType(task);
        _distributeBountyBasedOnExecutionTime(task, claimBounty, sig);

        emit TaskExecuted(claimBounty.receiver, task.id);
    }

    function redeemFromExpiredTask(uint256 taskIdx) external {
        Task memory task = _tasks[taskIdx];
        if (block.timestamp <= task.scheduleAt) {
            revert TaskNotExpiredYet();
        }
        if (msg.sender != task.subscriber) revert OnlyFromTaskSubscriber();

        _tasks[taskIdx] = _tasks[_tasks.length - 1];
        _tasks.pop();

        // task still accessible after pop
        _redeemFundBasedOnTaskType(task);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    function _sanityCheck(
        uint64 scheduleAt,
        address tokenAddress,
        address callingAddress,
        uint256 jitBounty,
        uint256 callAmount,
        TaskType taskType,
        bytes memory callData
    ) internal pure {
        if (
            scheduleAt == 0
                || (
                    (taskType != TaskType.NATIVE_TRANSFER && taskType != TaskType.CONTRACT_CALL_WITH_NATIVE)
                        && tokenAddress == address(0)
                ) || callingAddress == address(0) || jitBounty == 0 || callAmount == 0
                || (taskType != TaskType.NATIVE_TRANSFER && callData.length == 0)
        ) {
            revert InvalidTaskInput();
        }
    }

    /// @dev setup all the prerequisites in order for the scheduled task to execute successfully
    function _setupForTask(TaskType taskType, address tokenAddress, uint256 jitBounty, uint256 callAmount) internal {
        uint256 protocolFee = jitBounty * _protocolFeeBP / _BASIS_POINTS;
        uint256 minRequiredAmount = jitBounty + protocolFee;

        // transfer the required funds to this contract
        if (taskType == TaskType.NATIVE_TRANSFER || taskType == TaskType.CONTRACT_CALL_WITH_NATIVE) {
            minRequiredAmount += callAmount;
        }
        if (msg.value != minRequiredAmount) revert InsufficientSetupFunds();

        if (taskType == TaskType.ERC20_TRANSFER || taskType == TaskType.CONTRACT_CALL_WITH_ERC20) {
            IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), callAmount);
        }
    }

    function _tryGetClosestToJITIdx(uint256 startingIdx)
        internal
        view
        returns (uint256 cloestToJITIdx, uint256 activeStartingIdx)
    {
        uint256 i = startingIdx != 0 ? startingIdx : 0;
        uint256 len = _tasks.length;
        bool foundActive;

        for (i; i < len; i++) {
            // task not expired yet
            if (block.timestamp <= _tasks[i].scheduleAt) {
                // find the starting index of active tasks
                if (!foundActive) {
                    activeStartingIdx = i;
                    foundActive = true;
                }
                // find the closest to JIT task index
                uint256 smallestGap = _tasks[i].scheduleAt - block.timestamp;
                cloestToJITIdx = i;
                // compare with the next active task
                if (i + 1 < len && _tasks[i + 1].scheduleAt - block.timestamp < smallestGap) {
                    smallestGap = _tasks[i + 1].scheduleAt - block.timestamp;
                    cloestToJITIdx = i + 1;
                }
            }
        }
        if (!foundActive) revert AllTasksExpired();
    }

    function _executeTaskBasedOnTaskType(Task memory task) internal {
        if (task.taskType == TaskType.NATIVE_TRANSFER) {
            payable(task.callingAddress).transfer(task.callAmount);
        }

        if (task.taskType == TaskType.CONTRACT_CALL_WITH_NATIVE) {
            (bool success, bytes memory data) = payable(task.callingAddress).call{value: task.callAmount}(task.callData);
            if (!success) revert TaskFailed(data);
        }
        if (task.taskType == TaskType.ERC20_TRANSFER || task.taskType == TaskType.CONTRACT_CALL_WITH_ERC20) {
            // Approve before allowing the callingAddress to handle the tokens
            if (task.taskType == TaskType.CONTRACT_CALL_WITH_ERC20) {
                IERC20(task.tokenAddress).approve(task.callingAddress, task.callAmount);
            }
            (bool success, bytes memory data) = task.callingAddress.call(task.callData);
            if (!success) revert TaskFailed(data);
        }
    }

    function _distributeBountyBasedOnExecutionTime(Task memory task, ClaimBounty memory claimBounty, bytes memory sig)
        internal
    {
        // block.timestamp must be <= task.scheduleAt at this point
        uint256 minsBeforeJIT = (task.scheduleAt - block.timestamp) / 1 minutes;
        uint256 finalBounty =
            task.jitBounty - (task.jitBounty * minsBeforeJIT * _bountyDecayBPPerMinute / _BASIS_POINTS);

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(_CLAIM_BOUNTY_TYPEHASH, claimBounty.receiver)));
        if (digest.recover(sig) != claimBounty.receiver) revert InvalidReceiverFromHookData();

        // transfer bounty to receiver
        payable(claimBounty.receiver).transfer(finalBounty);
        // transfer remaining bounty back to subscriber
        if (task.jitBounty > finalBounty) payable(task.subscriber).transfer(task.jitBounty - finalBounty);
    }

    function _redeemFundBasedOnTaskType(Task memory task) internal {
        if (task.taskType == TaskType.NATIVE_TRANSFER || task.taskType == TaskType.CONTRACT_CALL_WITH_NATIVE) {
            payable(task.subscriber).transfer(task.jitBounty + task.callAmount);
        }
        if (task.taskType == TaskType.ERC20_TRANSFER || task.taskType == TaskType.CONTRACT_CALL_WITH_ERC20) {
            payable(task.subscriber).transfer(task.jitBounty);
            IERC20(task.callingAddress).safeTransfer(task.subscriber, task.callAmount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    function withdrawFee(address feeReceiver) external onlyOwner {
        payable(feeReceiver).transfer(address(this).balance);
    }

    function setHookAddress(address hookAddress) external onlyOwner {
        _hookAddress = hookAddress;
    }

    function setBountyDecayBPPerMinute(uint16 bountyDecayBPPerMinute) external onlyOwner {
        if (bountyDecayBPPerMinute > _BASIS_POINTS) revert InvalidBountyDecayBPPerMinute();
        _bountyDecayBPPerMinute = bountyDecayBPPerMinute;
    }

    function setProtocolFeeBP(uint16 protocolFeeBP) external onlyOwner {
        if (protocolFeeBP > _BASIS_POINTS) revert InvalidProtocolFeeBP();
        _protocolFeeBP = protocolFeeBP;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function hasPendingTask() public view returns (bool) {
        return _tasks.length > 0;
    }

    function hasActiveTask() external view returns (bool) {
        if (_tasks.length == 0) return false;

        for (uint256 i; i < _tasks.length; i++) {
            // task not expired yet
            if (block.timestamp <= _tasks[i].scheduleAt) {
                return true;
            }
        }
        return false;
    }

    function getNumOfTasks() external view returns (uint256) {
        return _tasks.length;
    }

    function getTasks() external view returns (Task[] memory) {
        return _tasks;
    }

    function getTask(uint256 taskIndex) external view returns (Task memory) {
        return _tasks[taskIndex];
    }

    function getHookAddress() external view returns (address) {
        return _hookAddress;
    }

    function getBountyDecayBPPerMinute() external view returns (uint16) {
        return _bountyDecayBPPerMinute;
    }

    function getProtocolFeeBP() external view returns (uint16) {
        return _protocolFeeBP;
    }
}
