// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {AutoMateHook} from "src/AutoMateHook.sol";
import {AutoMate} from "src/AutoMate.sol";

import "src/interfaces/IAutoMate.sol";

contract AutoMateSetup is Test, Deployers {
    // Use the libraries
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Contracts
    AutoMate public autoMate;
    AutoMateHook public autoMateHook;
    PoolId public poolId;

    uint256 private constant _BASIS_POINTS = 10000;
    bytes32 private constant _CLAIM_BOUNTY_TYPEHASH = keccak256("ClaimBounty(address receiver)");

    // Native tokens are represented by address(0)
    Currency ethCurrency = Currency.wrap(address(0));
    MockERC20 token0;
    MockERC20 token1;

    IPoolManager public poolManager;

    // Users
    mapping(uint256 userId => uint256 privateKey) public userPrivateKeys;
    address public alice;
    address public bob;
    address public cat;

    // For AutoMate test cases
    uint256 taskId;
    uint64 defaultScheduleAt = uint64(block.timestamp + 1 hours);
    uint256 defaultBounty = 100 ether;
    uint256 defaultTransferAmount = 10000 ether;
    uint256 defaultProtocolFeeBP = 1000;
    uint256 protocolFee = (defaultBounty * defaultProtocolFeeBP) / _BASIS_POINTS;
    uint256 bountyDecayBPPerMinute = 100;

    // receive the bounty if any
    fallback() external payable {}

    modifier userPrank(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        // 1) Deploy v4 core contracts (PoolManager, periphery Router contracts for swapping, modifying liquidity etc)
        deployFreshManagerAndRouters();

        // 2) Deploy two test tokens
        (currency0, currency1) = deployMintAndApprove2Currencies();
        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        // 3) Deploy our AutoMate contract
        autoMate = new AutoMate(1000, 100); // 10% fee, 1% decay per min

        // 4) Deploy Hook contract to specified address
        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        // Daily auction, 1% drop
        deployCodeTo("AutoMateHook.sol", abi.encode(manager, address(autoMate)), hookAddress);
        autoMateHook = AutoMateHook(hookAddress);

        // 5) Set the hook address in the AutoMate contract
        autoMate.setHookAddress(address(autoMateHook));

        // 6) Initialize a pool with these two tokens
        (key,) = initPool(
            currency0,
            currency1,
            autoMateHook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1, // Initial Sqrt(P) value = 1
            ZERO_BYTES // No additional `initData`
        );
        poolId = key.toId();

        // 7) Add initial liquidity to the pool
        token0.approve(hookAddress, type(uint256).max);
        token1.approve(hookAddress, type(uint256).max);
        token0.approve(address(autoMate), type(uint256).max);
        token1.approve(address(autoMate), type(uint256).max);

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 10 ether, salt: ""}),
            ZERO_BYTES
        );
        // Some liquidity from -120 to +120 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10 ether, salt: ""}),
            ZERO_BYTES
        );
        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: ""
            }),
            ZERO_BYTES
        );

        // 8) Set up users
        setUpUsers();
    }

    function setUpUsers() public {
        // Private Keys
        userPrivateKeys[0] = 1;
        userPrivateKeys[1] = 2;
        userPrivateKeys[2] = 3;

        // Addresses
        alice = vm.addr(userPrivateKeys[0]);
        bob = vm.addr(userPrivateKeys[1]);
        cat = vm.addr(userPrivateKeys[2]);
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(cat, "cat");

        // ETH distribution
        deal(alice, 110 ether);
        deal(bob, 1 ether);
        deal(cat, 1 ether);

        // Token distribution
        deal(address(token0), alice, 10000 ether);
        deal(address(token0), cat, 10000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        TEST UTILS
    //////////////////////////////////////////////////////////////*/
    /// @dev subscribe task (ERC20 Transfer) with specific user
    function subscribeTaskBy(address subscriber, uint256 transferAmount)
        public
        userPrank(subscriber)
        returns (uint256 id)
    {
        bytes memory taskInfo = abi.encode(
            defaultBounty,
            IAutoMate.TaskType.ERC20_TRANSFER,
            address(token0),
            uint64(block.timestamp + 1 hours), // Scheduled at 1 hour from now
            transferAmount,
            abi.encodeCall(IERC20.transfer, (bob, transferAmount))
        );

        IERC20(address(token0)).approve(address(autoMate), transferAmount);
        vm.expectEmit(address(autoMate));
        emit IAutoMate.TaskSubscribed(address(subscriber), 0);
        id = autoMate.subscribeTask{value: defaultBounty + protocolFee}(taskInfo);
    }

    function subscribeNativeTransferTaskBy(address subscriber, uint256 bounty, uint256 transferAmount)
        public
        userPrank(subscriber)
        returns (uint256 id)
    {
        protocolFee = (bounty * defaultProtocolFeeBP) / _BASIS_POINTS;
        bytes memory taskInfo = abi.encode(
            bounty,
            IAutoMate.TaskType.NATIVE_TRANSFER,
            address(token0),
            uint64(block.timestamp + 1 hours), // Scheduled at 1 hour from now
            transferAmount,
            ZERO_BYTES
        );

        vm.expectEmit(address(autoMate));
        emit IAutoMate.TaskSubscribed(address(subscriber), 0);
        id = autoMate.subscribeTask{value: bounty + protocolFee + transferAmount}(taskInfo);
    }

    /// @dev get EIP712 signature for a receiver
    function getEIP712Signature(IAutoMate.ClaimBounty memory claimBounty, uint256 privateKey, bytes32 domainSeparator)
        public
        pure
        returns (bytes memory sig)
    {
        (uint8 v, bytes32 r, bytes32 s) = _getEIP712SignatureRaw(claimBounty, privateKey, domainSeparator);
        return bytes.concat(r, s, bytes1(v));
    }

    function approveNecessarySpenders(address user, uint256 amount) public userPrank(user) {
        address[2] memory toApprove = [address(swapRouter), address(autoMate)];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token0.approve(toApprove[i], amount);
            token1.approve(toApprove[i], amount);
        }
    }

    function calculateRemainingBountyByMin(uint256 minExecutedTooEarly)
        public
        view
        returns (uint256 remainingBounty, uint256 decayAmount)
    {
        remainingBounty = defaultBounty;
        decayAmount = (defaultBounty * minExecutedTooEarly * bountyDecayBPPerMinute) / _BASIS_POINTS;
        remainingBounty -= decayAmount;
    }

    function _getEIP712SignatureRaw(
        IAutoMate.ClaimBounty memory claimBounty,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 msgHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, _hash(claimBounty)));

        (v, r, s) = vm.sign(privateKey, msgHash);
    }

    // computes the hash of a permit
    function _hash(IAutoMate.ClaimBounty memory claimBounty) internal pure returns (bytes32) {
        return keccak256(abi.encode(_CLAIM_BOUNTY_TYPEHASH, claimBounty.receiver));
    }

    function _normalize(uint256 amount) internal pure returns (uint256) {
        return amount / 10 ** 18;
    }
}
