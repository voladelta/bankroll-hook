// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { BankrollHook } from "../../../src/bankroll/BankrollHook.sol";
import { BankrollHookFactory, BankrollRouterFactory } from "../../../src/bankroll/BankrollHookFactory.sol";
import { BankrollRouter, IWETH } from "../../../src/bankroll/BankrollRouter.sol";
import { IBankrollHook } from "../../../src/bankroll/interfaces/IBankrollHook.sol";
import { IRandomnessAdapter } from "../../../src/bankroll/interfaces/IRandomnessAdapter.sol";
import { BankrollConfig, GameState } from "../../../src/bankroll/types/BankrollTypes.sol";
import { MockToken, MockWeth } from "../helpers/MockAssets.sol";
import { MockRandomnessAdapter } from "../helpers/MockRandomnessAdapter.sol";

contract BankrollInvariantHandler is Deployers {
    BankrollHook public immutable hook;
    BankrollRouter public immutable bankrollRouter;
    MockToken public immutable token;
    MockWeth public immutable weth;
    MockRandomnessAdapter public immutable randomness;

    uint256 public successfulCalls;
    uint256 public revertedCalls;
    uint256 public skippedCalls;
    bool public terminalObserved;
    bool public lifecycleRevived;
    bool public doublePaymentObserved;

    mapping(uint64 ticketId => uint8 successfulClaims) public claimCount;

    constructor(
        BankrollHook hook_,
        BankrollRouter bankrollRouter_,
        MockToken token_,
        MockWeth weth_,
        MockRandomnessAdapter randomness_
    ) {
        hook = hook_;
        bankrollRouter = bankrollRouter_;
        token = token_;
        weth = weth_;
        randomness = randomness_;
        token_.approve(address(bankrollRouter_), type(uint256).max);
        weth_.approve(address(hook_), type(uint256).max);
    }

    function fund(uint96 rawAssets) external {
        _observeLifecycle();
        if (hook.state() != GameState.Funding || block.number >= hook.fundingCloseBlockExclusive()) return _skip();

        uint256 balance = weth.balanceOf(address(this));
        if (balance == 0) return _skip();
        uint256 assets = bound(uint256(rawAssets), 1, balance);
        try hook.depositBankroll(assets) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function withdrawFunding(uint96 rawShares) external {
        _observeLifecycle();
        if (hook.state() != GameState.Funding || block.number >= hook.fundingCloseBlockExclusive()) return _skip();

        uint256 shares = hook.bankrollShares(address(this));
        if (shares == 0) return _skip();
        uint256 amount = bound(uint256(rawShares), 1, shares);
        try hook.withdrawBankrollDuringFunding(amount) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function finishFunding() external {
        _observeLifecycle();
        if (hook.state() != GameState.Funding) return _skip();

        vm.roll(hook.fundingCloseBlockExclusive());
        if (hook.bankrollAssets() >= hook.minimumBankrollAssets()) {
            try hook.activateGame() {
                ++successfulCalls;
            } catch {
                ++revertedCalls;
            }
        } else {
            try hook.cancelUnfundedGame() {
                ++successfulCalls;
            } catch {
                ++revertedCalls;
            }
        }
        _observeLifecycle();
    }

    function wagerBuy(uint96 rawAmount, uint96 rawStake) external {
        _observeLifecycle();
        if (hook.state() != GameState.Active) return _skip();

        uint256 amount = bound(uint256(rawAmount), 0.1 ether, 2 ether);
        uint256 maximumStake = amount / 5;
        uint128 stake = uint128(bound(uint256(rawStake), hook.minimumWager(), maximumStake));
        try bankrollRouter.gameSwapExactInput{ value: amount + stake }(
            true, amount, 0, stake, MIN_PRICE_LIMIT, block.timestamp, address(this)
        ) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function wagerSell(uint96 rawAmount, uint96 rawStake) external {
        _observeLifecycle();
        if (hook.state() != GameState.Active) return _skip();

        uint256 amount = bound(uint256(rawAmount), 0.1 ether, 2 ether);
        uint128 stake = uint128(bound(uint256(rawStake), hook.minimumWager(), amount / 10));
        try bankrollRouter.gameSwapExactInput{ value: stake }(
            false, amount, 0, stake, MAX_PRICE_LIMIT, block.timestamp, address(this)
        ) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function close() external {
        _observeLifecycle();
        if (hook.state() != GameState.Active) return _skip();

        vm.roll(hook.closeBlockExclusive());
        try hook.closeGame() {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function requestRandomness() external {
        _observeLifecycle();
        if (hook.state() != GameState.Closed || hook.ticketCount() == 0) return _skip();

        uint256 fee = randomness.fee();
        try hook.requestRandomness{ value: fee }(fee) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function fulfillAndPull(bytes32 word) external {
        _observeLifecycle();
        if (hook.state() != GameState.RandomnessRequested) return _skip();

        randomness.fulfill(hook.requestKey(), word);
        try hook.pullRandomness() {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function expireRandomness() external {
        _observeLifecycle();
        GameState current = hook.state();
        if (current == GameState.Closed) {
            vm.roll(uint256(hook.closedAtBlock()) + hook.requestGraceBlocks());
        } else if (current == GameState.RandomnessRequested) {
            vm.roll(uint256(hook.requestBlock()) + hook.fulfillmentTimeoutBlocks());
        } else {
            return _skip();
        }

        try hook.expireRandomness() {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function settle(uint64 rawTicketId) external {
        _observeLifecycle();
        uint64 count = hook.ticketCount();
        if (hook.state() != GameState.Seeded || count == 0) return _skip();

        uint64 ticketId = uint64(bound(rawTicketId, 1, count));
        try hook.settleTicket(ticketId) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function claim(uint64 rawTicketId) external {
        _observeLifecycle();
        uint64 count = hook.ticketCount();
        if (count == 0) return _skip();

        uint64 ticketId = uint64(bound(rawTicketId, 1, count));
        try hook.claimTicket(ticketId) {
            ++successfulCalls;
            uint8 claims = ++claimCount[ticketId];
            if (claims > 1) doublePaymentObserved = true;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function claimProgrammableFee() external {
        _observeLifecycle();
        if (hook.programmableLiability() == 0) return _skip();

        vm.prank(hook.PROGRAMMABLE_FEE_OWNER());
        try hook.claimProgrammableFeesTo(address(this)) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function finalize() external {
        _observeLifecycle();
        GameState current = hook.state();
        bool allowed = current == GameState.Expired
            || (current == GameState.Seeded && hook.settledCount() == hook.ticketCount())
            || (current == GameState.Closed && hook.ticketCount() == 0);
        if (!allowed) return _skip();

        try hook.finalizeGame() {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function redeem(uint96 rawShares) external {
        _observeLifecycle();
        GameState current = hook.state();
        if (current != GameState.Finalized && current != GameState.Cancelled) return _skip();

        uint256 shares = hook.bankrollShares(address(this));
        if (shares == 0) return _skip();
        uint256 amount = bound(uint256(rawShares), 1, shares);
        try hook.redeemBankroll(amount) {
            ++successfulCalls;
        } catch {
            ++revertedCalls;
        }
        _observeLifecycle();
    }

    function _observeLifecycle() private {
        GameState current = hook.state();
        if (terminalObserved && current == GameState.Active) lifecycleRevived = true;
        if (current == GameState.Expired || current == GameState.Finalized || current == GameState.Cancelled) {
            terminalObserved = true;
        }
    }

    function _skip() private {
        ++skippedCalls;
        _observeLifecycle();
    }
}

contract BankrollSolvencyInvariantTest is Deployers {
    BankrollHook internal hook;
    BankrollRouter internal bankrollRouter;
    MockToken internal token;
    MockWeth internal weth;
    MockRandomnessAdapter internal randomness;
    BankrollInvariantHandler internal handler;

    function setUp() public {
        deployFreshManagerAndRouters();
        vm.deal(address(this), 1_000_000 ether);
        token = new MockToken("Bankroll Launch Token", "BANK");
        weth = new MockWeth();
        randomness = new MockRandomnessAdapter(0.01 ether);
        token.mint(address(this), 1_000_000_000 ether);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        BankrollConfig memory config = BankrollConfig({
            minimumWager: 0.01 ether,
            maximumWager: 10 ether,
            minimumBankrollAssets: 10 ether,
            fundingBlocks: 10,
            activeBlocks: 20,
            requestGraceBlocks: 10,
            fulfillmentTimeoutBlocks: 20,
            maximumSettlementBatch: 16
        });

        BankrollRouterFactory routerFactory = new BankrollRouterFactory();
        BankrollHookFactory hookFactory = new BankrollHookFactory(routerFactory);
        bytes memory constructorArgs = abi.encode(
            manager,
            address(this),
            address(token),
            IERC20(address(weth)),
            IRandomnessAdapter(address(randomness)),
            config
        );
        bytes memory initCode = abi.encodePacked(type(BankrollHook).creationCode, constructorArgs);
        (, bytes32 salt) = HookMiner.find(
            address(hookFactory), hookFactory.REQUIRED_HOOK_FLAGS(), type(BankrollHook).creationCode, constructorArgs
        );
        (hook, bankrollRouter) = hookFactory.deploy(
            salt,
            initCode,
            manager,
            address(this),
            IERC20(address(token)),
            IWETH(address(weth)),
            IRandomnessAdapter(address(randomness)),
            config
        );

        PoolKey memory hookKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: 0,
            tickSpacing: 200,
            hooks: hook
        });
        manager.initialize(hookKey, SQRT_PRICE_1_1);
        ModifyLiquidityParams memory liquidityParams =
            ModifyLiquidityParams({ tickLower: -200, tickUpper: 200, liquidityDelta: 100_000 ether, salt: 0 });
        modifyLiquidityRouter.modifyLiquidity{ value: 200_000 ether }(hookKey, liquidityParams, ZERO_BYTES);

        handler = new BankrollInvariantHandler(hook, bankrollRouter, token, weth, randomness);
        token.mint(address(handler), 1_000_000 ether);
        weth.deposit{ value: 100 ether }();
        assertTrue(weth.transfer(address(handler), 100 ether));
        vm.deal(address(handler), 10_000 ether);

        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = handler.fund.selector;
        selectors[1] = handler.withdrawFunding.selector;
        selectors[2] = handler.finishFunding.selector;
        selectors[3] = handler.wagerBuy.selector;
        selectors[4] = handler.wagerSell.selector;
        selectors[5] = handler.close.selector;
        selectors[6] = handler.requestRandomness.selector;
        selectors[7] = handler.fulfillAndPull.selector;
        selectors[8] = handler.expireRandomness.selector;
        selectors[9] = handler.settle.selector;
        selectors[10] = handler.claim.selector;
        selectors[11] = handler.finalize.selector;
        selectors[12] = handler.redeem.selector;
        selectors[13] = handler.claimProgrammableFee.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    function invariant_wethBalanceCoversEveryGameLiability() public view {
        assertGe(weth.balanceOf(address(hook)), hook.accountedWeth());
    }

    function invariant_reservedExposureStaysInsideBothCaps() public view {
        assertLe(hook.reservedExposure(), hook.bankrollAssets());
        assertLe(hook.reservedExposure(), (hook.bankrollAssets() * 8000) / 10_000);
    }

    function invariant_terminalLifecycleCannotReturnToActive() public view {
        assertFalse(handler.lifecycleRevived());
    }

    function invariant_ticketCannotPayTwice() public view {
        assertFalse(handler.doublePaymentObserved());
        assertLe(hook.settledCount(), hook.ticketCount());
        assertLe(hook.ticketCount(), hook.MAX_TICKETS());
    }

    function invariant_bankrollSharesStayConserved() public view {
        assertEq(hook.bankrollShares(address(handler)), hook.totalBankrollShares());
    }

    function invariant_programmableFeeLiabilityHasNativeClaimBacking() public view {
        assertEq(hook.programmableLiability(), hook.totalProgrammableFeesAccrued());
        assertEq(manager.balanceOf(address(hook), 0), hook.programmableLiability());
    }
}
