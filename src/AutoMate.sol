// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AutoMate is Ownable {
    using SafeERC20 for IERC20;

    event TaskSubscribed(address indexed subscriber, uint256 taskId);

    error OnlyFromAuthorizedHook();
    error ExceedsMaxInterval();
    error InsufficientFunds();
    error TaskFailed(bytes data);

    uint256 constant MAX_INTERVAL_IN_SECS = 365 days;
    uint256 constant BASIS_POINTS = 10000;

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

    mapping(uint256 taskId => Task) public tasks;
    mapping(address subscriber => uint256 taskId) public subscribersTaskIds;

    uint16 protocolFeeBP;
    address hookAddress;

    modifier onlyFromHook() {
        if (msg.sender != hookAddress) {
            revert OnlyFromAuthorizedHook();
        }
        _;
    }

    constructor(address _hookAddress, uint16 _protocolFeeBP) Ownable(msg.sender) {
        hookAddress = _hookAddress;
        protocolFeeBP = _protocolFeeBP;
    }

    function subscribe(
        address callingContract,
        uint32 intervalInSecs,
        uint40 startTs,
        bool isRecurring,
        uint256 values,
        bytes calldata callData,
        TaskInput calldata taskInput
    ) external payable {
        if (intervalInSecs > MAX_INTERVAL_IN_SECS) {
            revert ExceedsMaxInterval();
        }

        uint256 taskId = getTaskId(intervalInSecs, startTs, isRecurring, values, callData);
        tasks[taskId] = Task(msg.sender, callingContract, intervalInSecs, startTs, isRecurring, values, callData);
        subscribersTaskIds[msg.sender] = taskId;

        _setupForTask(callingContract, taskInput);

        emit TaskSubscribed(msg.sender, taskId);
    }

    function triggerTask(uint256 taskId) external onlyFromHook {
        Task memory task = tasks[taskId];

        // execute the task
        (bool success, bytes memory data) = address(task.callingContract).call(task.callData);
        if (!success) {
            revert TaskFailed(data);
        }

        // remove the task if it's not a recurring task
        if (!task.isRecurring) {
            delete tasks[taskId];
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
    function setHookAddress(address _hookAddress) external onlyOwner {
        hookAddress = _hookAddress;
    }

    function setProtocolFeeBP(uint16 _protocolFeeBP) external onlyOwner {
        protocolFeeBP = _protocolFeeBP;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function getTaskId(uint32 intervalInSecs, uint40 startTs, bool isRecurring, uint256 values, bytes calldata callData)
        public
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(intervalInSecs, startTs, isRecurring, values, callData)));
    }
}
