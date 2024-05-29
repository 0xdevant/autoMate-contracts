// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAutoMate} from "./interfaces/IAutoMate.sol";

contract AutoMate is Ownable, IAutoMate {
    using SafeERC20 for IERC20;

    // only allow at most monthly task to be scheduled
    uint256 constant MAX_INTERVAL_IN_HOURS = 720;
    uint256 constant BASIS_POINTS = 10000;

    Task[] private _tasks;

    address private _hookAddress;
    uint16 private _protocolFeeBP;

    modifier onlyFromHook() {
        if (msg.sender != _hookAddress) {
            revert OnlyFromAuthorizedHook();
        }
        _;
    }

    constructor(address hookAddress, uint16 protocolFeeBP) Ownable(msg.sender) {
        _hookAddress = hookAddress;
        protocolFeeBP = protocolFeeBP;
    }

    function subscribeTask(bytes memory taskInfo) external payable returns (uint256 taskId) {
        (
            TaskType taskType,
            address callingContract,
            uint40 startTs,
            uint16 intervalInHours,
            uint16 lastForInHours,
            uint256 totalAmounts,
            uint256 totalValues,
            bytes memory callData
        ) = abi.decode(taskInfo, (TaskType, address, uint40, uint16, uint16, uint256, uint256, bytes));
        if (intervalInHours > MAX_INTERVAL_IN_HOURS) {
            revert ExceedsMaxInterval();
        }

        taskId = _tasks.length;
        Task memory task = Task(
            taskId,
            msg.sender,
            taskType,
            callingContract,
            startTs,
            intervalInHours,
            lastForInHours,
            totalAmounts,
            totalValues,
            callData
        );
        _tasks.push(task);

        // TODO: make use of Oracle to take protocol fee in USD term from totalAmounts / totalValues, to compensate for the custom price curve

        _setupForTask(taskType, callingContract, totalAmounts, totalValues);

        emit TaskSubscribed(msg.sender, taskId);
    }

    function executeTask(uint256 taskId) external onlyFromHook {
        Task memory task = _tasks[taskId];

        // execute the task
        (bool success, bytes memory data) = address(task.callingContract).call(task.callData);
        if (!success) {
            revert TaskFailed(data);
        }

        // remove the task if it's not a recurring task
        if (task.intervalInHours == task.lastForInHours) {
            _tasks[taskId] = _tasks[_tasks.length - 1];
            _tasks.pop();
        }
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    /// @dev setup all the prerequisites in order for the scheduled task to execute successfully
    function _setupForTask(TaskType taskType, address callingContract, uint256 totalAmounts, uint256 totalValues)
        internal
    {
        if (taskType == TaskType.NATIVE_TRANSFER) {
            if (msg.value < totalValues) {
                revert InsufficientFunds();
            }
        }
        if (taskType == TaskType.ERC20_TRANSFER) {
            IERC20(callingContract).safeTransferFrom(msg.sender, address(this), totalAmounts);
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
    function getTask(uint256 taskId) external view override returns (Task memory) {
        return _tasks[taskId];
    }

    function getProtocolFeeBP() external view returns (uint16) {
        return _protocolFeeBP;
    }
}
