// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAutoMate} from "./interfaces/IAutoMate.sol";

contract AutoMate is Ownable, IAutoMate {
    using SafeERC20 for IERC20;

    uint256 constant MAX_INTERVAL_IN_SECS = 365 days;
    uint256 constant BASIS_POINTS = 10000;

    mapping(uint256 taskId => Task) private _tasks;
    mapping(address subscriber => uint256[] taskId) private _subscribersTaskIds;

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

    function subscribeTask(Task calldata task, TaskInput calldata taskInput) external payable {
        if (task.intervalInSecs > MAX_INTERVAL_IN_SECS) {
            revert ExceedsMaxInterval();
        }

        uint256 taskId =
            getTaskId(msg.sender, task.intervalInSecs, task.startTs, task.isRecurring, task.values, task.callData);
        _tasks[taskId] = Task(
            msg.sender,
            task.callingContract,
            task.intervalInSecs,
            task.startTs,
            task.isRecurring,
            task.values,
            task.callData
        );
        _subscribersTaskIds[msg.sender].push(taskId);

        _setupForTask(task.callingContract, taskInput);

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
        if (!task.isRecurring) {
            delete _tasks[taskId];
        }
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    /// @dev setup all the prerequisites in order for the scheduled task to execute successfully
    function _setupForTask(address callingContract, TaskInput calldata taskInput) internal {
        if (taskInput.taskType == TaskType.NATIVE_TRANSFER) {
            if (msg.value < taskInput.totalAmount) {
                revert InsufficientFunds();
            }
        }
        if (taskInput.taskType == TaskType.ERC20_TRANSFER) {
            IERC20(callingContract).safeTransferFrom(msg.sender, address(this), taskInput.totalAmount);
        }
        if (taskInput.taskType == TaskType.ERC721_TRANSFER) {
            IERC721(callingContract).safeTransferFrom(msg.sender, address(this), taskInput.totalAmount);
        }
        if (taskInput.taskType == TaskType.ERC1155_TRANSFER) {
            IERC1155(callingContract).safeTransferFrom(
                msg.sender, address(this), taskInput.tokenId, taskInput.totalAmount, ""
            );
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

    function getTaskId(
        address subscriber,
        uint32 intervalInSecs,
        uint40 startTs,
        bool isRecurring,
        uint256 values,
        bytes calldata callData
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(subscriber, intervalInSecs, startTs, isRecurring, values, callData)));
    }

    function getTask(uint256 taskId) external view override returns (Task memory) {
        return _tasks[taskId];
    }

    function getSubscribersTaskIds(address subscriber) external view override returns (uint256[] memory) {
        return _subscribersTaskIds[subscriber];
    }

    function getProtocolFeeBP() external view returns (uint16) {
        return _protocolFeeBP;
    }
}
