// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseHook } from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { ModifyLiquidityParams, SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { BankrollHook } from "../../src/bankroll/BankrollHook.sol";
import { BankrollHookFactory, BankrollRouterFactory } from "../../src/bankroll/BankrollHookFactory.sol";
import { BankrollRouter, IWETH } from "../../src/bankroll/BankrollRouter.sol";
import { IRandomnessAdapter } from "../../src/bankroll/interfaces/IRandomnessAdapter.sol";
import { IBankrollHook } from "../../src/bankroll/interfaces/IBankrollHook.sol";
import { BankrollHookData } from "../../src/bankroll/libraries/BankrollHookData.sol";
import { BankrollConfig, GameState, Ticket, TicketStatus } from "../../src/bankroll/types/BankrollTypes.sol";
import { MockToken, MockWeth } from "./helpers/MockAssets.sol";
import { MockRandomnessAdapter } from "./helpers/MockRandomnessAdapter.sol";

contract BankrollLifecycleTest is Deployers {
    BankrollHook internal hook;
    BankrollRouter internal bankrollRouter;
    BankrollHookFactory internal hookFactory;
    BankrollRouterFactory internal routerFactory;
    MockToken internal token;
    MockWeth internal weth;
    MockRandomnessAdapter internal randomness;
    PoolKey internal hookKey;
    BankrollConfig internal config;

    function setUp() public {
        deployFreshManagerAndRouters();
        vm.deal(address(this), 1_000_000 ether);
        token = new MockToken("Bankroll Launch Token", "BANK");
        weth = new MockWeth();
        randomness = new MockRandomnessAdapter(0.01 ether);
        token.mint(address(this), 1_000_000_000 ether);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        config = BankrollConfig({
            minimumWager: 0.01 ether,
            maximumWager: 10 ether,
            minimumBankrollAssets: 10 ether,
            fundingBlocks: 10,
            activeBlocks: 20,
            requestGraceBlocks: 10,
            fulfillmentTimeoutBlocks: 20,
            maximumSettlementBatch: 16
        });

        routerFactory = new BankrollRouterFactory();
        hookFactory = new BankrollHookFactory(routerFactory);
        bytes memory constructorArgs = abi.encode(
            manager,
            address(this),
            address(token),
            IERC20(address(weth)),
            IRandomnessAdapter(address(randomness)),
            config
        );
        bytes memory initCode = abi.encodePacked(type(BankrollHook).creationCode, constructorArgs);
        (address predicted, bytes32 salt) = HookMiner.find(
            address(hookFactory), hookFactory.REQUIRED_HOOK_FLAGS(), type(BankrollHook).creationCode, constructorArgs
        );
        bytes32 routerSalt = keccak256(abi.encode("BANKROLL_ROUTER_V1", predicted));
        address predictedRouter = routerFactory.predict(
            routerSalt, manager, IBankrollHook(predicted), IERC20(address(token)), IWETH(address(weth))
        );
        (hook, bankrollRouter) =
            hookFactory.deploy(salt, initCode, manager, IERC20(address(token)), IWETH(address(weth)));
        assertEq(address(hook), predicted);
        assertEq(address(bankrollRouter), predictedRouter);

        hookKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: 0,
            tickSpacing: 200,
            hooks: hook
        });
        manager.initialize(hookKey, SQRT_PRICE_1_1);
        LIQUIDITY_PARAMS =
            ModifyLiquidityParams({ tickLower: -200, tickUpper: 200, liquidityDelta: 100_000 ether, salt: 0 });
        modifyLiquidityRouter.modifyLiquidity{ value: 200_000 ether }(hookKey, LIQUIDITY_PARAMS, ZERO_BYTES);

        weth.deposit{ value: 100 ether }();
        weth.approve(address(hook), type(uint256).max);
        hook.depositBankroll(100 ether);
        vm.roll(hook.fundingCloseBlockExclusive());
        hook.activateGame();
        token.approve(address(bankrollRouter), type(uint256).max);
        token.approve(address(swapRouter), type(uint256).max);
    }

    function testPermissionMaskAndCanonicalPool() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeInitialize);
        assertTrue(permissions.afterInitialize);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertTrue(permissions.beforeSwapReturnDelta);
        assertTrue(permissions.afterSwapReturnDelta);
        assertEq(uint160(address(hook)) & hookFactory.ALL_HOOK_MASK(), 0x30CC);
        assertEq(hook.canonicalPoolId(), PoolId.unwrap(hookKey.toId()));
    }

    function testBuyWagerCompletesFiniteLifecycle() public {
        uint256 accountedBefore = hook.accountedWeth();
        (uint256 amountOut,) = bankrollRouter.gameSwapExactInput{ value: 1.1 ether }(
            true, 1 ether, 0, 0.1 ether, MIN_PRICE_LIMIT, block.timestamp, address(this)
        );
        assertGt(amountOut, 0);
        assertEq(hook.ticketCount(), 1);
        assertEq(hook.openStakeLiability(), 0.1 ether);
        assertEq(hook.accountedWeth(), accountedBefore + 0.1 ether);
        Ticket memory created = hook.ticket(1);
        assertEq(uint256(created.status), uint256(TicketStatus.Open));

        vm.roll(hook.closeBlockExclusive());
        hook.closeGame();
        hook.requestRandomness{ value: 0.01 ether }(0.01 ether);
        randomness.fulfill(hook.requestKey(), bytes32(uint256(7)));
        hook.pullRandomness();

        uint256 beforeSettlement = hook.accountedWeth();
        hook.settleTicket(1);
        assertEq(hook.accountedWeth(), beforeSettlement);
        hook.finalizeGame();
        assertEq(uint256(hook.state()), uint256(GameState.Finalized));
        assertEq(hook.settledCount(), 1);
    }

    function testRandomnessTimeoutRefundsStake() public {
        bankrollRouter.gameSwapExactInput{ value: 1.1 ether }(
            true, 1 ether, 0, 0.1 ether, MIN_PRICE_LIMIT, block.timestamp, address(this)
        );
        vm.roll(hook.closeBlockExclusive());
        hook.closeGame();
        vm.roll(block.number + hook.requestGraceBlocks());
        hook.expireRandomness();
        assertEq(hook.playerClaimLiability(), 0.1 ether);
        uint256 balanceBefore = weth.balanceOf(address(this));
        hook.claimTicket(1);
        assertEq(weth.balanceOf(address(this)), balanceBefore + 0.1 ether);
    }

    function testSellWagerCreatesTicketFromExecutedNativeOutput() public {
        (uint256 amountOut,) = bankrollRouter.gameSwapExactInput{ value: 0.05 ether }(
            false, 0.5 ether, 0, 0.05 ether, MAX_PRICE_LIMIT, block.timestamp, address(this)
        );
        assertGt(amountOut, 0);
        Ticket memory created = hook.ticket(1);
        assertEq(created.stake, 0.05 ether);
        assertEq(uint256(created.status), uint256(TicketStatus.Open));
        assertEq(hook.ticketCount(), 1);
    }

    function testProgrammableOwnerCanClaimToChosenRecipient() public {
        _ordinarySwap(true, -int256(1 ether), 1 ether);
        uint256 liability = hook.programmableLiability();
        address recipient = makeAddr("programmable fee recipient");

        vm.prank(makeAddr("not owner"));
        vm.expectRevert();
        hook.claimProgrammableFeesTo(payable(recipient));

        uint256 beforeBalance = recipient.balance;
        vm.prank(hook.PROGRAMMABLE_FEE_OWNER());
        hook.claimProgrammableFeesTo(payable(recipient));
        assertEq(recipient.balance, beforeBalance + liability);
        assertEq(hook.programmableLiability(), 0);
        assertEq(hook.totalProgrammableFeesAccrued(), 0);
    }

    function testOrdinarySwapsCoverAllFourNativeQuoteQuadrants() public {
        uint256 beforeFees = hook.totalProgrammableFeesAccrued();
        _ordinarySwap(true, -int256(1 ether), 1 ether);
        uint256 afterBuyExactInput = hook.totalProgrammableFeesAccrued();
        assertGt(afterBuyExactInput, beforeFees);

        _ordinarySwap(true, int256(0.01 ether), 1 ether);
        uint256 afterBuyExactOutput = hook.totalProgrammableFeesAccrued();
        assertGt(afterBuyExactOutput, afterBuyExactInput);

        _ordinarySwap(false, -int256(0.01 ether), 0);
        uint256 afterSellExactInput = hook.totalProgrammableFeesAccrued();
        assertGt(afterSellExactInput, afterBuyExactOutput);

        _ordinarySwap(false, int256(0.005 ether), 0);
        assertGt(hook.totalProgrammableFeesAccrued(), afterSellExactInput);
        assertEq(hook.ticketCount(), 0);
        assertEq(hook.programmableLiability(), hook.totalProgrammableFeesAccrued());
    }

    function testWrongManagerAndMalformedGameDataCannotEnterCallback() public {
        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT });

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeSwap(address(bankrollRouter), hookKey, params, hex"01");

        vm.expectRevert(abi.encodeWithSelector(BankrollHookData.InvalidHookDataLength.selector, uint256(1)));
        vm.prank(address(manager));
        hook.beforeSwap(address(bankrollRouter), hookKey, params, hex"01");
    }

    function testOrdinaryRouterCannotUseGameHookData() public {
        bytes memory hookData = BankrollHookData.encode(keccak256("unstaged wager"));

        vm.expectRevert(abi.encodeWithSelector(BankrollHook.UnauthorizedRouter.selector, address(swapRouter)));
        vm.prank(address(manager));
        hook.beforeSwap(
            address(swapRouter),
            hookKey,
            SwapParams({ zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT }),
            hookData
        );
    }

    function testPendingWagerCannotBeReplayedOrConsumedInAnotherBlock() public {
        bytes32 pendingId = keccak256("one use only");
        _stagePendingWager(pendingId, 0.1 ether);

        vm.expectRevert(abi.encodeWithSelector(BankrollHook.PendingWagerAlreadyExists.selector, pendingId));
        vm.prank(address(bankrollRouter));
        hook.stageWager(pendingId, address(this), 0.1 ether);

        vm.roll(block.number + 1);
        vm.expectRevert(abi.encodeWithSelector(BankrollHook.PendingWagerWrongBlock.selector, pendingId));
        vm.prank(address(manager));
        hook.beforeSwap(
            address(bankrollRouter),
            hookKey,
            SwapParams({ zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT }),
            BankrollHookData.encode(pendingId)
        );
    }

    function testExactOutputWagerIsRejected() public {
        bytes32 pendingId = keccak256("exact output wager");
        _stagePendingWager(pendingId, 0.1 ether);

        vm.expectRevert(BankrollHook.WagerExactOutputUnsupported.selector);
        vm.prank(address(manager));
        hook.beforeSwap(
            address(bankrollRouter),
            hookKey,
            SwapParams({ zeroForOne: true, amountSpecified: int256(0.01 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT }),
            BankrollHookData.encode(pendingId)
        );
    }

    function testVolumeCapFailureRevertsTheCompleteWagerTransaction() public {
        uint256 accountedBefore = hook.accountedWeth();
        uint64 nonceBefore = bankrollRouter.nonce();

        vm.expectRevert();
        bankrollRouter.gameSwapExactInput{ value: 0.15 ether }(
            true, 0.1 ether, 0, 0.05 ether, MIN_PRICE_LIMIT, block.timestamp, address(this)
        );

        assertEq(hook.accountedWeth(), accountedBefore);
        assertEq(bankrollRouter.nonce(), nonceBefore);
        assertEq(weth.balanceOf(address(bankrollRouter)), 0);
        assertEq(hook.ticketCount(), 0);
    }

    function testRandomnessCannotExpireEarlyOrAfterFulfillment() public {
        _createTicketAndClose();
        uint256 expiryBlock = uint256(hook.closedAtBlock()) + hook.requestGraceBlocks();
        vm.roll(expiryBlock - 1);
        vm.expectRevert(BankrollHook.RandomnessDeadlineNotReached.selector);
        hook.expireRandomness();

        hook.requestRandomness{ value: 0.01 ether }(0.01 ether);
        randomness.fulfill(hook.requestKey(), bytes32(uint256(11)));
        vm.roll(uint256(hook.requestBlock()) + hook.fulfillmentTimeoutBlocks());
        vm.expectRevert(BankrollHook.RandomnessAlreadyFinal.selector);
        hook.expireRandomness();
    }

    function testTicketCannotClaimTwice() public {
        _createTicketAndClose();
        vm.roll(uint256(hook.closedAtBlock()) + hook.requestGraceBlocks());
        hook.expireRandomness();

        hook.claimTicket(1);
        vm.expectRevert(abi.encodeWithSelector(BankrollHook.TicketNotClaimable.selector, uint64(1)));
        hook.claimTicket(1);
    }

    function testTicketCannotSettleTwice() public {
        _createTicketAndClose();
        hook.requestRandomness{ value: 0.01 ether }(0.01 ether);
        randomness.fulfill(hook.requestKey(), bytes32(uint256(7)));
        hook.pullRandomness();

        hook.settleTicket(1);
        vm.expectRevert(abi.encodeWithSelector(BankrollHook.TicketNotOpen.selector, uint64(1)));
        hook.settleTicket(1);
    }

    function testOnlyBoundRouterCanStageWagers() public {
        address attacker = makeAddr("untrusted router");
        vm.expectRevert(abi.encodeWithSelector(BankrollHook.UnauthorizedRouter.selector, attacker));
        vm.prank(attacker);
        hook.stageWager(keccak256("unauthorized"), attacker, 0.1 ether);
    }

    function testStakeBoundsAndBankrollCapacityAreEnforced() public {
        vm.expectRevert(abi.encodeWithSelector(BankrollHook.StakeBelowMinimum.selector, 0.009 ether, 0.01 ether));
        vm.prank(address(bankrollRouter));
        hook.stageWager(keccak256("below minimum"), address(this), 0.009 ether);

        vm.expectRevert(abi.encodeWithSelector(BankrollHook.StakeAboveMaximum.selector, 10.01 ether, 10 ether));
        vm.prank(address(bankrollRouter));
        hook.stageWager(keccak256("above maximum"), address(this), 10.01 ether);

        _fundRouterWeth(80 ether);
        for (uint256 index; index < 8; ++index) {
            vm.prank(address(bankrollRouter));
            hook.stageWager(keccak256(abi.encode("capacity", index)), address(this), 10 ether);
        }

        vm.expectRevert(
            abi.encodeWithSelector(BankrollHook.InsufficientBankrollCapacity.selector, 3.2 ether, 9.6 ether)
        );
        vm.prank(address(bankrollRouter));
        hook.stageWager(keccak256("over capacity"), address(this), 10 ether);
    }

    function testRouterDeadlineNativeValueAndMinimumOutputAreAtomic() public {
        vm.warp(block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(BankrollRouter.DeadlineExpired.selector, uint256(1), uint256(2)));
        bankrollRouter.gameSwapExactInput{ value: 1.1 ether }(
            true, 1 ether, 0, 0.1 ether, MIN_PRICE_LIMIT, block.timestamp - 1, address(this)
        );

        vm.expectRevert(abi.encodeWithSelector(BankrollRouter.InvalidNativeValue.selector, 1.1 ether, 1 ether));
        bankrollRouter.gameSwapExactInput{ value: 1 ether }(
            true, 1 ether, 0, 0.1 ether, MIN_PRICE_LIMIT, block.timestamp, address(this)
        );

        uint256 accountedBefore = hook.accountedWeth();
        uint64 nonceBefore = bankrollRouter.nonce();
        vm.expectPartialRevert(BankrollRouter.MinimumOutputNotMet.selector);
        bankrollRouter.gameSwapExactInput{ value: 1.1 ether }(
            true, 1 ether, type(uint256).max, 0.1 ether, MIN_PRICE_LIMIT, block.timestamp, address(this)
        );
        assertEq(hook.accountedWeth(), accountedBefore);
        assertEq(bankrollRouter.nonce(), nonceBefore);
        assertEq(hook.ticketCount(), 0);
    }

    function testAlternatePoolAndDirectRouterCallbackAreRejected() public {
        PoolKey memory alternateKey = hookKey;
        alternateKey.tickSpacing = 400;
        vm.expectRevert(BankrollHook.InvalidPoolKey.selector);
        vm.prank(address(manager));
        hook.beforeSwap(
            address(bankrollRouter),
            alternateKey,
            SwapParams({ zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT }),
            ZERO_BYTES
        );

        vm.expectRevert(abi.encodeWithSelector(BankrollRouter.UnauthorizedCallback.selector, address(this)));
        bankrollRouter.unlockCallback(ZERO_BYTES);
    }

    function testRequestedRandomnessTimeoutRefundsAndFinalStateCannotReactivate() public {
        _createTicketAndClose();
        hook.requestRandomness{ value: 0.01 ether }(0.01 ether);
        vm.roll(uint256(hook.requestBlock()) + hook.fulfillmentTimeoutBlocks());
        hook.expireRandomness();
        hook.finalizeGame();

        assertEq(uint256(hook.state()), uint256(GameState.Finalized));
        vm.expectRevert(abi.encodeWithSelector(BankrollHook.InvalidState.selector, GameState.Finalized));
        hook.activateGame();

        uint256 balanceBefore = weth.balanceOf(address(this));
        hook.claimTicket(1);
        assertEq(weth.balanceOf(address(this)), balanceBefore + 0.1 ether);
    }

    function testProgrammableFeeCannotBeClaimedTwiceOrToZeroAddress() public {
        _ordinarySwap(true, -int256(1 ether), 1 ether);

        vm.startPrank(hook.PROGRAMMABLE_FEE_OWNER());
        vm.expectRevert(BankrollHook.ZeroAddress.selector);
        hook.claimProgrammableFeesTo(address(0));
        hook.claimProgrammableFees();
        vm.expectRevert(BankrollHook.NoFeesToClaim.selector);
        hook.claimProgrammableFees();
        vm.stopPrank();
    }

    function _createTicketAndClose() private {
        bankrollRouter.gameSwapExactInput{ value: 1.1 ether }(
            true, 1 ether, 0, 0.1 ether, MIN_PRICE_LIMIT, block.timestamp, address(this)
        );
        vm.roll(hook.closeBlockExclusive());
        hook.closeGame();
    }

    function _stagePendingWager(bytes32 pendingId, uint128 stake) private {
        _fundRouterWeth(stake);
        vm.prank(address(bankrollRouter));
        hook.stageWager(pendingId, address(this), stake);
    }

    function _fundRouterWeth(uint256 amount) private {
        vm.deal(address(bankrollRouter), amount);
        vm.prank(address(bankrollRouter));
        weth.deposit{ value: amount }();
    }

    function _ordinarySwap(bool zeroForOne, int256 amountSpecified, uint256 value) private returns (BalanceDelta) {
        return swapRouter.swap{ value: value }(
            hookKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ZERO_BYTES
        );
    }
}
