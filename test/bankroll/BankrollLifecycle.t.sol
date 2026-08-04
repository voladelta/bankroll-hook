// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
