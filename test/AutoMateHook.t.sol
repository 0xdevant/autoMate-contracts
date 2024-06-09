// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import {AutoMateSetup} from "test/AutoMateSetup.sol";
import {AutoMate} from "src/AutoMate.sol";

import "src/interfaces/IAutoMate.sol";

contract TestAutoMateHook is AutoMateSetup {
    bytes32 private constant _SWAPPER_TYPEHASH = keccak256("Swapper(address executor)");

    function test_swap() public {
        vm.label(cat, "cat");
        deal(alice, 1.01 ether);
        deal(bob, 1 ether);
        deal(cat, 1 ether);

        deal(address(token0), alice, 10000 ether);
        deal(address(token0), cat, 10000 ether);
        vm.prank(alice);
        IERC20(address(token0)).approve(address(autoMate), 10000 ether);
        vm.startPrank(cat);
        IERC20(address(token0)).approve(address(autoMate), 10000 ether);
        IERC20(address(token0)).approve(address(swapRouter), 10000 ether);
        vm.stopPrank();

        console2.log("### BEFORE SUB ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
        vm.prank(alice);
        subscribeTaskBy(alice);

        console2.log("\n ### AFTER SUB ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));

        console2.log("\n ### BEFORE SWAP ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("eth balanceOf(cat):", cat.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
        console2.log("token 0 balanceOf(bob):", _normalize(token0.balanceOf(bob)));
        console2.log("token 0 balanceOf(cat):", _normalize(token0.balanceOf(cat)));

        // Perform a swap and execute task //
        vm.warp(block.timestamp);
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!

        IAutoMate.Swapper memory swapper = IAutoMate.Swapper({executor: cat});
        bytes memory sig = _getPermitSignature(swapper, 1, autoMate.DOMAIN_SEPARATOR());
        bytes memory encodedHookData = abi.encode(swapper, sig);

        vm.prank(cat);
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, encodedHookData);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        console2.log("\n ### AFTER SWAP ###");
        console2.log("eth balanceOf(alice):", alice.balance);
        console2.log("eth balanceOf(cat):", cat.balance);
        console2.log("token 0 balanceOf(alice):", _normalize(token0.balanceOf(alice)));
        console2.log("token 0 balanceOf(bob):", _normalize(token0.balanceOf(bob)));
        console2.log("token 0 balanceOf(cat):", _normalize(token0.balanceOf(cat)));
    }

    function _getPermitSignature(IAutoMate.Swapper memory swapper, uint256 privateKey, bytes32 domainSeparator)
        internal
        pure
        returns (bytes memory sig)
    {
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignatureRaw(swapper, privateKey, domainSeparator);
        return bytes.concat(r, s, bytes1(v));
    }

    function _getPermitSignatureRaw(IAutoMate.Swapper memory swapper, uint256 privateKey, bytes32 domainSeparator)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, _hash(swapper)));

        (v, r, s) = vm.sign(privateKey, msgHash);
    }

    function _hash(IAutoMate.Swapper memory swapper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_SWAPPER_TYPEHASH, swapper.executor));
    }

    function _normalize(uint256 amount) internal pure returns (uint256) {
        return amount / 10 ** 18;
    }
}
