// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { CurrencySettler } from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";

import { IBankrollHook } from "./interfaces/IBankrollHook.sol";
import { BankrollHookData } from "./libraries/BankrollHookData.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
}

/// @notice Narrow exact-input router for one Bankroll Hook pool.
contract BankrollRouter is IUnlockCallback, ReentrancyGuardTransient {
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;

    struct CallbackData {
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    IPoolManager public immutable poolManager;
    IBankrollHook public immutable hook;
    IERC20 public immutable launchedToken;
    IWETH public immutable weth;
    uint64 public nonce;

    error DeadlineExpired(uint256 deadline, uint256 currentTime);
    error ExactInputOnly();
    error InvalidNativeValue(uint256 expected, uint256 actual);
    error MinimumOutputNotMet(uint256 minimum, uint256 actual);
    error PendingWagerNotConsumed(bytes32 pendingId);
    error UnauthorizedCallback(address caller);
    error UnexpectedDelta();
    error UnexpectedUnlockResult();
    error ZeroAddress();
    error ZeroAmount();

    event GameSwap(
        bytes32 indexed pendingId,
        address indexed player,
        address indexed recipient,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut,
        uint256 stake
    );

    constructor(IPoolManager poolManager_, IBankrollHook hook_, IERC20 launchedToken_, IWETH weth_) {
        if (
            address(poolManager_) == address(0) || address(hook_) == address(0) || address(launchedToken_) == address(0)
                || address(weth_) == address(0)
        ) revert ZeroAddress();
        poolManager = poolManager_;
        hook = hook_;
        launchedToken = launchedToken_;
        weth = weth_;
        IERC20(address(weth_)).forceApprove(address(hook_), type(uint256).max);
    }

    receive() external payable { }

    function gameSwapExactInput(
        bool zeroForOne,
        uint256 amountIn,
        uint256 minimumAmountOut,
        uint128 stake,
        uint160 sqrtPriceLimitX96,
        uint256 deadline,
        address recipient
    ) external payable nonReentrant returns (uint256 amountOut, uint64 userNonce) {
        // The deadline is a user-selected expiry guard; small validator timestamp drift cannot redirect funds.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (amountIn == 0 || stake == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        if (zeroForOne) {
            uint256 expected = amountIn + stake;
            if (msg.value != expected) revert InvalidNativeValue(expected, msg.value);
        } else {
            if (msg.value != stake) revert InvalidNativeValue(stake, msg.value);
            launchedToken.safeTransferFrom(msg.sender, address(this), amountIn);
        }

        weth.deposit{ value: stake }();
        userNonce = ++nonce;
        bytes32 pendingId = keccak256(
            abi.encode("BANKROLL_PENDING_V1", block.chainid, address(hook), address(this), msg.sender, userNonce)
        );
        hook.stageWager(pendingId, msg.sender, stake);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(launchedToken)),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne, amountSpecified: -amountIn.toInt256(), sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        bytes memory result = poolManager.unlock(
            abi.encode(CallbackData({ key: key, params: params, hookData: BankrollHookData.encode(pendingId) }))
        );
        if (result.length != 32) revert UnexpectedUnlockResult();
        BalanceDelta delta = abi.decode(result, (BalanceDelta));
        if (hook.pendingWagerExists(pendingId)) revert PendingWagerNotConsumed(pendingId);

        if (zeroForOne) {
            if (delta.amount1() <= 0) revert UnexpectedDelta();
            amountOut = uint128(delta.amount1());
            launchedToken.safeTransfer(recipient, amountOut);
        } else {
            if (delta.amount0() <= 0) revert UnexpectedDelta();
            amountOut = uint128(delta.amount0());
            (bool sent,) = recipient.call{ value: amountOut }("");
            if (!sent) revert UnexpectedDelta();
        }
        if (amountOut < minimumAmountOut) revert MinimumOutputNotMet(minimumAmountOut, amountOut);
        emit GameSwap(pendingId, msg.sender, recipient, zeroForOne, amountIn, amountOut, stake);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert UnauthorizedCallback(msg.sender);
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);

        int256 delta0 = int256(delta.amount0());
        int256 delta1 = int256(delta.amount1());
        if (delta0 < 0) data.key.currency0.settle(poolManager, address(this), SignedMath.abs(delta0), false);
        if (delta1 < 0) data.key.currency1.settle(poolManager, address(this), SignedMath.abs(delta1), false);
        if (delta0 > 0) data.key.currency0.take(poolManager, address(this), delta0.toUint256(), false);
        if (delta1 > 0) data.key.currency1.take(poolManager, address(this), delta1.toUint256(), false);
        return abi.encode(delta);
    }
}
