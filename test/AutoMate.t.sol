// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

// Our Contracts
import {AutoMateSetup} from "test/AutoMateSetup.sol";
import {AutoMate} from "src/AutoMate.sol";
import {AutoMateHook} from "src/AutoMateHook.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "src/interfaces/IAutoMate.sol";

contract TestAutoMate is AutoMateSetup {
    function test_SubscribeTask_CanSubscribeTask() public {
        bytes memory taskInfo = abi.encode(
            IAutoMate.TaskType.ERC20_TRANSFER,
            IAutoMate.TaskInterval.DAILY,
            uint40(720),
            address(token0),
            1000 ether,
            0,
            abi.encodeCall(IERC20.transfer, (user, 1 ether))
        );
        uint256 taskId = autoMate.subscribeTask(key, taskInfo);
        assertEq(taskId, 0);
    }

    // function test_ExecuteTask() public {
    //     bytes memory taskInfo = abi.encode(
    //         IAutoMate.TaskType.ERC20_TRANSFER,
    //         IAutoMate.TaskInterval.DAILY,
    //         uint40(720),
    //         address(token0),
    //         uint256(1000 ether),
    //         uint256(0),
    //         bytes("")
    //     );
    //     autoMate.subscribeTask(key, taskInfo);
    //     autoMateHook.beforeSwap(
    //         user,
    //         key,
    //         IPoolManager.SwapParams(true, -1000, TickMath.MIN_SQRT_PRICE + 1),
    //         ""
    //     );

    //     assertEq(token0.balanceOf(user), 0);
    // }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    function test_SetHookAddress_RevertIfNotOwnerSetHookAddress() public {
        vm.prank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(1)
            )
        );
        autoMate.setHookAddress(address(autoMateHook));
    }

    function test_SetProtocolFeeBP_RevertIfNotOwnerSetProtocolFeeBP() public {
        vm.prank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                address(1)
            )
        );
        autoMate.setProtocolFeeBP(4000);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function test_GetTaskCategoryId_CanGetTaskCategroyId() public {}

    function test_HasPendingTaskInCategory_CanGetGetTaskInCategoryLength()
        public
    {}

    function test_GetNumOfTasksInCategory_CanGetNumOfTasks() public {}

    function test_GetTaskInCategory_CanGetTaskInCategory() public {}

    function test_GetTask_CanGetTask() public {}

    function test_GetNextTaskIndex_CanGetNextTaskIndex() public {}

    function test_GetProtocolFeeBP_CanGetProtocolFeeBP() public {}
}
