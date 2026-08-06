// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { BaseHook } from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import { CurrencySettler } from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { IBankrollHook } from "./interfaces/IBankrollHook.sol";
import { IRandomnessAdapter } from "./interfaces/IRandomnessAdapter.sol";
import { BankrollHookData } from "./libraries/BankrollHookData.sol";
import { BankrollMath } from "./libraries/BankrollMath.sol";
import { ProgrammableFeeMath } from "./libraries/ProgrammableFeeMath.sol";
import { BankrollConfig, GameState, PendingWager, Ticket, TicketStatus } from "./types/BankrollTypes.sol";

/// @notice One finite, fixed-odds bankroll season for one native ETH/token Uniswap v4 pool.
/// @dev Prototype only. This contract is not independently reviewed, deployed, routed or available.
contract BankrollHook is BaseHook, IUnlockCallback, ReentrancyGuardTransient, IBankrollHook {
    using CurrencySettler for Currency;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_TICKETS = 64;
    address public constant PROGRAMMABLE_FEE_OWNER = 0x4957f49620AFf3Adbbe8195a4f633E49cc93376c;
    bytes4 private constant CLAIM_UNLOCK_MAGIC = bytes4(keccak256("BANKROLL_PROGRAMMABLE_FEE_V1_CLAIM"));

    address public immutable factory;
    address public immutable registrar;
    address public immutable launchedToken;
    IERC20 public immutable weth;
    IRandomnessAdapter public immutable randomnessAdapter;

    uint128 public immutable minimumWager;
    uint128 public immutable maximumWager;
    uint128 public immutable minimumBankrollAssets;
    uint64 public immutable fundingBlocks;
    uint64 public immutable activeBlocks;
    uint64 public immutable requestGraceBlocks;
    uint64 public immutable fulfillmentTimeoutBlocks;
    uint16 public immutable maximumSettlementBatch;

    address public gameRouter;
    bytes32 public canonicalPoolId;
    bool public canonicalPoolRegistered;

    GameState public state;
    uint64 public fundingStartBlock;
    uint64 public fundingCloseBlockExclusive;
    uint64 public startBlock;
    uint64 public closeBlockExclusive;
    uint64 public closedAtBlock;
    uint64 public requestBlock;

    uint64 public ticketCount;
    uint64 public settledCount;
    bytes32 public requestKey;
    bytes32 public seasonSeed;
    bool public refundMode;

    uint256 public bankrollAssets;
    uint256 public openStakeLiability;
    uint256 public playerClaimLiability;
    uint256 public reservedExposure;
    uint256 public totalBankrollShares;
    uint256 public totalProgrammableFeesAccrued;

    uint256 private _pendingSpecifiedQuotePoolAmountPlusOne;
    uint256 private _pendingGrossQuoteAmount;

    mapping(address account => uint256 shares) public bankrollShares;
    mapping(bytes32 pendingId => PendingWager wager) private _pendingWagers;
    mapping(uint64 ticketId => Ticket ticketData) private _tickets;
    mapping(bytes32 poolId => mapping(address currency => mapping(address owner => uint256 amount))) private
        _programmableLiability;

    error AlreadyInitialized();
    error BalanceInvariantViolation(uint256 balance, uint256 accounted);
    error ExactPaymentRequired(uint256 expected, uint256 actual);
    error FundingClosed();
    error FundingDeadlineNotReached();
    error GameEntryClosed();
    error GameNotClosable();
    error InsufficientBankrollCapacity(uint256 available, uint256 required);
    error InsufficientShares(uint256 available, uint256 required);
    error InvalidConfiguration();
    error InvalidHookAddress(address actual);
    error InvalidLpFee(uint24 actual);
    error InvalidPoolKey();
    error InvalidState(GameState actual);
    error InvalidTickSpacing(int24 actual);
    error MinimumBankrollAlreadyReached();
    error MinimumBankrollNotReached();
    error NoFeesToClaim();
    error NothingToClaim();
    error PartialFillUnsupported(uint256 expected, uint256 actual);
    error PendingWagerAlreadyExists(bytes32 pendingId);
    error PendingWagerNotFound(bytes32 pendingId);
    error PendingWagerWrongBlock(bytes32 pendingId);
    error RandomnessAlreadyFinal();
    error RandomnessDeadlineNotReached();
    error RandomnessNotFulfilled();
    error RedemptionNotAvailable();
    error StakeAboveMaximum(uint256 stake, uint256 maximum);
    error StakeBelowMinimum(uint256 stake, uint256 minimum);
    error StakeExceedsExecutedVolumeCap(uint256 stake, uint256 maximum);
    error TicketCapacityReached();
    error TicketNotClaimable(uint64 ticketId);
    error TicketNotFound(uint64 ticketId);
    error TicketNotOpen(uint64 ticketId);
    error UnauthorizedInitializer(address caller);
    error UnauthorizedProgrammableClaim(address caller);
    error UnauthorizedRouter(address caller);
    error UnexpectedUnlockData();
    error UnexpectedUnlockResult();
    error WagerExactOutputUnsupported();
    error ZeroAddress();
    error ZeroAmount();

    event RouterBound(address indexed router);
    event FundingOpened(bytes32 indexed poolId, uint64 startBlock, uint64 closeBlockExclusive);
    event BankrollDeposited(address indexed provider, uint256 assets, uint256 shares, uint256 bankrollAssets);
    event BankrollWithdrawnDuringFunding(
        address indexed provider, uint256 assets, uint256 shares, uint256 bankrollAssets
    );
    event GameActivated(uint64 indexed startBlock, uint64 indexed closeBlockExclusive, uint256 bankrollAssets);
    event GameCancelledUnfunded(uint256 bankrollAssets, uint256 minimumBankrollAssets);
    event GameClosed(uint64 indexed closedAtBlock, uint64 ticketCount);
    event WagerStaged(bytes32 indexed pendingId, address indexed player, uint256 stake, uint256 exposure);
    event TicketCreated(
        uint64 indexed ticketId,
        address indexed player,
        bool indexed isBuy,
        uint256 grossQuote,
        uint256 stake,
        uint256 grossPayout,
        uint256 exposure
    );
    event RandomnessRequested(bytes32 indexed requestKey, uint64 indexed requestBlock, uint256 fee);
    event RandomnessConsumed(bytes32 indexed requestKey, bytes32 indexed seasonSeed);
    event RandomnessExpired(uint256 refundableStakeLiability);
    event TicketSettled(uint64 indexed ticketId, address indexed player, bool won, uint256 claimAmount);
    event TicketClaimed(uint64 indexed ticketId, address indexed player, uint256 amount);
    event GameFinalized(uint256 bankrollAssets, uint256 playerClaimLiability);
    event BankrollRedeemed(address indexed provider, uint256 shares, uint256 assets);
    event ProgrammableFeeAccrued(
        bytes32 indexed poolId, address indexed owner, address indexed swapSender, uint256 grossQuote, uint256 fee
    );
    event ProgrammableFeesClaimed(
        bytes32 indexed poolId, address indexed owner, address indexed recipient, uint256 amount
    );

    constructor(
        IPoolManager poolManager_,
        address registrar_,
        address launchedToken_,
        IERC20 weth_,
        IRandomnessAdapter randomnessAdapter_,
        BankrollConfig memory config
    ) BaseHook(poolManager_) {
        if (
            address(poolManager_) == address(0) || registrar_ == address(0) || launchedToken_ == address(0)
                || address(weth_) == address(0) || address(randomnessAdapter_) == address(0)
        ) revert ZeroAddress();
        if (
            config.minimumWager < 2 || config.minimumWager > config.maximumWager || config.minimumBankrollAssets == 0
                || config.fundingBlocks == 0 || config.activeBlocks == 0 || config.requestGraceBlocks == 0
                || config.fulfillmentTimeoutBlocks == 0 || config.maximumSettlementBatch == 0
                || config.maximumSettlementBatch > 16
        ) revert InvalidConfiguration();

        factory = msg.sender;
        registrar = registrar_;
        launchedToken = launchedToken_;
        weth = weth_;
        randomnessAdapter = randomnessAdapter_;
        minimumWager = config.minimumWager;
        maximumWager = config.maximumWager;
        minimumBankrollAssets = config.minimumBankrollAssets;
        fundingBlocks = config.fundingBlocks;
        activeBlocks = config.activeBlocks;
        requestGraceBlocks = config.requestGraceBlocks;
        fulfillmentTimeoutBlocks = config.fulfillmentTimeoutBlocks;
        maximumSettlementBatch = config.maximumSettlementBatch;
    }

    function bindRouter(address router) external {
        if (msg.sender != factory || gameRouter != address(0)) revert UnauthorizedRouter(msg.sender);
        if (router == address(0)) revert ZeroAddress();
        gameRouter = router;
        emit RouterBound(router);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function configurationHash() external view returns (bytes32) {
        return keccak256(
            abi.encode(
                address(poolManager),
                factory,
                registrar,
                launchedToken,
                address(weth),
                address(randomnessAdapter),
                gameRouter,
                minimumWager,
                maximumWager,
                minimumBankrollAssets,
                fundingBlocks,
                activeBlocks,
                requestGraceBlocks,
                fulfillmentTimeoutBlocks,
                maximumSettlementBatch
            )
        );
    }

    function pendingWagerExists(bytes32 pendingId) external view override returns (bool) {
        return _pendingWagers[pendingId].exists;
    }

    function ticket(uint64 ticketId) external view returns (Ticket memory) {
        return _tickets[ticketId];
    }

    function accountedWeth() public view returns (uint256) {
        return bankrollAssets + openStakeLiability + playerClaimLiability;
    }

    function availableExposure() public view returns (uint256) {
        uint256 utilizationAvailable = BankrollMath.utilizationLimit(bankrollAssets);
        if (reservedExposure >= utilizationAvailable || reservedExposure >= bankrollAssets) return 0;
        return Math.min(utilizationAvailable - reservedExposure, bankrollAssets - reservedExposure);
    }

    function quoteTicket(uint256 stake) external pure returns (uint256 grossPayout, uint256 exposure) {
        return BankrollMath.quoteTicket(stake);
    }

    function maxStakeForGrossQuote(uint256 grossQuote) external pure returns (uint256) {
        return BankrollMath.maxStakeForGrossQuote(grossQuote);
    }

    function programmableLiability() public view returns (uint256) {
        return _programmableLiability[canonicalPoolId][address(0)][PROGRAMMABLE_FEE_OWNER];
    }

    function derivedTicketState(uint64 ticketId) external view returns (TicketStatus) {
        return _tickets[ticketId].status;
    }

    function ticketRefundable(uint64 ticketId) external view returns (bool) {
        return refundMode && _tickets[ticketId].status == TicketStatus.Open;
    }

    function depositBankroll(uint256 assets) external nonReentrant {
        if (state != GameState.Funding) revert InvalidState(state);
        if (block.number >= fundingCloseBlockExclusive) revert FundingClosed();
        if (assets == 0) revert ZeroAmount();
        weth.safeTransferFrom(msg.sender, address(this), assets);
        bankrollShares[msg.sender] += assets;
        totalBankrollShares += assets;
        bankrollAssets += assets;
        _assertWethSolvency();
        emit BankrollDeposited(msg.sender, assets, assets, bankrollAssets);
    }

    function withdrawBankrollDuringFunding(uint256 shares) external nonReentrant {
        if (state != GameState.Funding) revert InvalidState(state);
        if (block.number >= fundingCloseBlockExclusive) revert FundingClosed();
        if (shares == 0) revert ZeroAmount();
        uint256 owned = bankrollShares[msg.sender];
        if (shares > owned) revert InsufficientShares(owned, shares);
        bankrollShares[msg.sender] = owned - shares;
        totalBankrollShares -= shares;
        bankrollAssets -= shares;
        weth.safeTransfer(msg.sender, shares);
        _assertWethSolvency();
        emit BankrollWithdrawnDuringFunding(msg.sender, shares, shares, bankrollAssets);
    }

    function activateGame() external {
        if (state != GameState.Funding) revert InvalidState(state);
        if (block.number < fundingCloseBlockExclusive) revert FundingDeadlineNotReached();
        if (bankrollAssets < minimumBankrollAssets) revert MinimumBankrollNotReached();
        state = GameState.Active;
        startBlock = block.number.toUint64();
        closeBlockExclusive = (block.number + activeBlocks).toUint64();
        emit GameActivated(startBlock, closeBlockExclusive, bankrollAssets);
    }

    function cancelUnfundedGame() external {
        if (state != GameState.Funding) revert InvalidState(state);
        if (block.number < fundingCloseBlockExclusive) revert FundingDeadlineNotReached();
        if (bankrollAssets >= minimumBankrollAssets) revert MinimumBankrollAlreadyReached();
        state = GameState.Cancelled;
        emit GameCancelledUnfunded(bankrollAssets, minimumBankrollAssets);
    }

    function stageWager(bytes32 pendingId, address player, uint128 stake) external override nonReentrant {
        if (msg.sender != gameRouter) revert UnauthorizedRouter(msg.sender);
        if (player == address(0)) revert ZeroAddress();
        if (state != GameState.Active || block.number >= closeBlockExclusive) revert GameEntryClosed();
        if (ticketCount >= MAX_TICKETS) revert TicketCapacityReached();
        if (stake < minimumWager) revert StakeBelowMinimum(stake, minimumWager);
        if (stake > maximumWager) revert StakeAboveMaximum(stake, maximumWager);
        if (_pendingWagers[pendingId].exists) revert PendingWagerAlreadyExists(pendingId);
        (, uint256 exposure) = BankrollMath.quoteTicket(stake);
        uint256 available = availableExposure();
        if (exposure > available) revert InsufficientBankrollCapacity(available, exposure);

        uint256 balanceBefore = weth.balanceOf(address(this));
        weth.safeTransferFrom(msg.sender, address(this), stake);
        uint256 received = weth.balanceOf(address(this)) - balanceBefore;
        if (received != stake) revert BalanceInvariantViolation(received, stake);

        openStakeLiability += stake;
        reservedExposure += exposure;
        _pendingWagers[pendingId] = PendingWager({
            player: player,
            stake: stake,
            exposure: exposure.toUint128(),
            stagedBlock: block.number.toUint64(),
            exists: true
        });
        _assertWethSolvency();
        emit WagerStaged(pendingId, player, stake, exposure);
    }

    function closeGame() public {
        if (state != GameState.Active) revert InvalidState(state);
        if (block.number < closeBlockExclusive && ticketCount < MAX_TICKETS) revert GameNotClosable();
        _closeGame();
    }

    function requestRandomness(uint256 maxFee) external payable nonReentrant {
        if (state == GameState.Active && (block.number >= closeBlockExclusive || ticketCount == MAX_TICKETS)) {
            _closeGame();
        }
        if (state != GameState.Closed || ticketCount == 0) revert InvalidState(state);
        uint256 fee = randomnessAdapter.quoteRequestFee();
        if (fee > maxFee) revert ExactPaymentRequired(fee, maxFee);
        if (msg.value != fee) revert ExactPaymentRequired(fee, msg.value);
        bytes32 context =
            keccak256(abi.encode("BANKROLL_SEASON_V1", block.chainid, address(this), canonicalPoolId, ticketCount));
        requestKey = randomnessAdapter.requestRandomness{ value: fee }(context, msg.sender);
        requestBlock = block.number.toUint64();
        state = GameState.RandomnessRequested;
        emit RandomnessRequested(requestKey, requestBlock, fee);
    }

    function pullRandomness() external nonReentrant {
        if (state != GameState.RandomnessRequested) revert InvalidState(state);
        if (!randomnessAdapter.fulfilled(requestKey)) revert RandomnessNotFulfilled();
        bytes32 word = randomnessAdapter.consumeRandomness(requestKey);
        seasonSeed = keccak256(
            abi.encode(
                "BANKROLL_SEASON_SEED_V1",
                word,
                block.chainid,
                address(this),
                canonicalPoolId,
                closedAtBlock,
                ticketCount
            )
        );
        state = GameState.Seeded;
        emit RandomnessConsumed(requestKey, seasonSeed);
    }

    function expireRandomness() external nonReentrant {
        if (state == GameState.Closed) {
            if (block.number < uint256(closedAtBlock) + requestGraceBlocks) revert RandomnessDeadlineNotReached();
        } else if (state == GameState.RandomnessRequested) {
            if (randomnessAdapter.fulfilled(requestKey)) revert RandomnessAlreadyFinal();
            if (block.number < uint256(requestBlock) + fulfillmentTimeoutBlocks) revert RandomnessDeadlineNotReached();
        } else {
            revert InvalidState(state);
        }
        uint256 refundable = openStakeLiability;
        playerClaimLiability += refundable;
        openStakeLiability = 0;
        reservedExposure = 0;
        refundMode = true;
        state = GameState.Expired;
        _assertWethSolvency();
        emit RandomnessExpired(refundable);
    }

    function settleTicket(uint64 ticketId) public {
        if (state != GameState.Seeded) revert InvalidState(state);
        Ticket storage item = _tickets[ticketId];
        if (item.status == TicketStatus.None) revert TicketNotFound(ticketId);
        if (item.status != TicketStatus.Open) revert TicketNotOpen(ticketId);

        uint256 exposure = uint256(item.grossPayout) - item.stake;
        bool won =
            (uint256(keccak256(abi.encode("BANKROLL_TICKET_V1", seasonSeed, canonicalPoolId, ticketId))) & 1) == 0;
        openStakeLiability -= item.stake;
        reservedExposure -= exposure;
        if (won) {
            bankrollAssets -= exposure;
            playerClaimLiability += item.grossPayout;
            item.status = TicketStatus.Won;
        } else {
            bankrollAssets += item.stake;
            item.status = TicketStatus.Lost;
        }
        ++settledCount;
        _assertWethSolvency();
        emit TicketSettled(ticketId, item.player, won, won ? item.grossPayout : 0);
    }

    function settleTickets(uint64 firstTicketId, uint16 count) external {
        if (count == 0 || count > maximumSettlementBatch) revert InvalidConfiguration();
        uint64 end = Math.min(uint256(firstTicketId) + count, uint256(ticketCount) + 1).toUint64();
        for (uint64 ticketId = firstTicketId; ticketId < end; ++ticketId) {
            if (_tickets[ticketId].status == TicketStatus.Open) settleTicket(ticketId);
        }
    }

    function claimTicket(uint64 ticketId) external nonReentrant returns (uint256 amount) {
        Ticket storage item = _tickets[ticketId];
        if (item.status == TicketStatus.None) revert TicketNotFound(ticketId);
        if (msg.sender != item.player) revert TicketNotClaimable(ticketId);
        if (refundMode && item.status == TicketStatus.Open) {
            amount = item.stake;
        } else if (item.status == TicketStatus.Won) {
            amount = item.grossPayout;
        } else {
            revert TicketNotClaimable(ticketId);
        }
        item.status = TicketStatus.Claimed;
        playerClaimLiability -= amount;
        weth.safeTransfer(msg.sender, amount);
        _assertWethSolvency();
        emit TicketClaimed(ticketId, msg.sender, amount);
    }

    function finalizeGame() external {
        bool allowed = (state == GameState.Closed && ticketCount == 0)
            || (state == GameState.Seeded && settledCount == ticketCount) || state == GameState.Expired;
        if (!allowed) revert InvalidState(state);
        state = GameState.Finalized;
        emit GameFinalized(bankrollAssets, playerClaimLiability);
    }

    function redeemBankroll(uint256 shares) external nonReentrant returns (uint256 assets) {
        if (state != GameState.Finalized && state != GameState.Cancelled) revert RedemptionNotAvailable();
        if (shares == 0) revert ZeroAmount();
        uint256 owned = bankrollShares[msg.sender];
        if (shares > owned) revert InsufficientShares(owned, shares);
        assets = BankrollMath.redemptionAssets(bankrollAssets, shares, totalBankrollShares);
        bankrollShares[msg.sender] = owned - shares;
        totalBankrollShares -= shares;
        bankrollAssets -= assets;
        weth.safeTransfer(msg.sender, assets);
        _assertWethSolvency();
        emit BankrollRedeemed(msg.sender, shares, assets);
    }

    function claimProgrammableFees() external returns (uint256) {
        return claimProgrammableFeesTo(PROGRAMMABLE_FEE_OWNER);
    }

    function claimProgrammableFeesTo(address recipient) public nonReentrant returns (uint256 amount) {
        if (msg.sender != PROGRAMMABLE_FEE_OWNER) revert UnauthorizedProgrammableClaim(msg.sender);
        if (recipient == address(0)) revert ZeroAddress();
        amount = programmableLiability();
        if (amount == 0) revert NoFeesToClaim();
        _programmableLiability[canonicalPoolId][address(0)][PROGRAMMABLE_FEE_OWNER] = 0;
        totalProgrammableFeesAccrued -= amount;
        bytes memory result = poolManager.unlock(abi.encode(CLAIM_UNLOCK_MAGIC, recipient, amount));
        if (result.length != 0) revert UnexpectedUnlockResult();
        emit ProgrammableFeesClaimed(canonicalPoolId, PROGRAMMABLE_FEE_OWNER, recipient, amount);
    }

    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        (bytes4 magic, address recipient, uint256 amount) = abi.decode(data, (bytes4, address, uint256));
        if (magic != CLAIM_UNLOCK_MAGIC || recipient == address(0) || amount == 0) revert UnexpectedUnlockData();
        Currency nativeCurrency = Currency.wrap(address(0));
        nativeCurrency.settle(poolManager, address(this), amount, true);
        nativeCurrency.take(poolManager, recipient, amount, false);
        return "";
    }

    function _beforeInitialize(address sender, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (state != GameState.Uninitialized || canonicalPoolRegistered) revert AlreadyInitialized();
        if (sender != registrar) revert UnauthorizedInitializer(sender);
        if (gameRouter == address(0)) revert UnauthorizedRouter(address(0));
        _validatePoolShape(key);
        canonicalPoolId = PoolId.unwrap(key.toId());
        canonicalPoolRegistered = true;
        return IHooks.beforeInitialize.selector;
    }

    function _afterInitialize(address sender, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        if (sender != registrar) revert UnauthorizedInitializer(sender);
        _requireCanonicalPool(key);
        if (state != GameState.Uninitialized) revert AlreadyInitialized();
        state = GameState.Funding;
        fundingStartBlock = block.number.toUint64();
        fundingCloseBlockExclusive = (block.number + fundingBlocks).toUint64();
        emit FundingOpened(canonicalPoolId, fundingStartBlock, fundingCloseBlockExclusive);
        return IHooks.afterInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _requireCanonicalPool(key);
        _validateGameHookData(sender, params, hookData);
        bool exactInput = params.amountSpecified < 0;
        bool quoteIsSpecified = params.zeroForOne == exactInput;
        if (!quoteIsSpecified) return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        if (_pendingSpecifiedQuotePoolAmountPlusOne != 0) revert InvalidConfiguration();

        uint256 quoteAmount = SignedMath.abs(params.amountSpecified);
        (uint256 grossQuote, uint256 fee) = exactInput
            ? (quoteAmount, ProgrammableFeeMath.feeForGross(quoteAmount))
            : ProgrammableFeeMath.grossUpExactOutput(quoteAmount);
        _accrueProgrammableFee(sender, grossQuote, fee);
        uint256 expectedPoolQuote = exactInput ? quoteAmount - fee : quoteAmount + fee;
        _pendingSpecifiedQuotePoolAmountPlusOne = expectedPoolQuote + 1;
        _pendingGrossQuoteAmount = grossQuote;
        BeforeSwapDelta hookDelta =
            fee == 0 ? BeforeSwapDeltaLibrary.ZERO_DELTA : toBeforeSwapDelta(fee.toInt256().toInt128(), 0);
        return (IHooks.beforeSwap.selector, hookDelta, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        _requireCanonicalPool(key);
        bool exactInput = params.amountSpecified < 0;
        bool quoteIsSpecified = params.zeroForOne == exactInput;
        uint256 grossQuote;
        uint256 fee = 0;

        if (quoteIsSpecified) {
            uint256 pendingPlusOne = _pendingSpecifiedQuotePoolAmountPlusOne;
            if (pendingPlusOne == 0) revert InvalidConfiguration();
            uint256 expected = pendingPlusOne - 1;
            grossQuote = _pendingGrossQuoteAmount;
            _pendingSpecifiedQuotePoolAmountPlusOne = 0;
            _pendingGrossQuoteAmount = 0;
            uint256 actual = SignedMath.abs(int256(delta.amount0()));
            if (actual != expected) revert PartialFillUnsupported(expected, actual);
        } else {
            grossQuote = SignedMath.abs(int256(delta.amount0()));
            fee = ProgrammableFeeMath.feeForGross(grossQuote);
            _accrueProgrammableFee(sender, grossQuote, fee);
        }

        if (hookData.length != 0) {
            if (!params.zeroForOne) {
                uint256 requestedTokenInput = SignedMath.abs(params.amountSpecified);
                uint256 actualTokenInput = SignedMath.abs(int256(delta.amount1()));
                if (actualTokenInput != requestedTokenInput) {
                    revert PartialFillUnsupported(requestedTokenInput, actualTokenInput);
                }
            }
            _consumeWager(params.zeroForOne, grossQuote, hookData);
        }
        return (IHooks.afterSwap.selector, fee == 0 ? int128(0) : fee.toInt256().toInt128());
    }

    function _validateGameHookData(address sender, SwapParams calldata params, bytes calldata hookData) private view {
        if (hookData.length == 0) return;
        if (sender != gameRouter) revert UnauthorizedRouter(sender);
        if (params.amountSpecified >= 0) revert WagerExactOutputUnsupported();
        bytes32 pendingId = BankrollHookData.decode(hookData);
        PendingWager storage wager = _pendingWagers[pendingId];
        if (!wager.exists) revert PendingWagerNotFound(pendingId);
        if (wager.stagedBlock != block.number) revert PendingWagerWrongBlock(pendingId);
        if (state != GameState.Active || block.number >= closeBlockExclusive) revert GameEntryClosed();
    }

    function _consumeWager(bool zeroForOne, uint256 grossQuote, bytes calldata hookData) private {
        bytes32 pendingId = BankrollHookData.decode(hookData);
        PendingWager memory wager = _pendingWagers[pendingId];
        if (!wager.exists) revert PendingWagerNotFound(pendingId);
        uint256 maximumStake = BankrollMath.maxStakeForGrossQuote(grossQuote);
        if (wager.stake > maximumStake) revert StakeExceedsExecutedVolumeCap(wager.stake, maximumStake);
        (uint256 grossPayout, uint256 exposure) = BankrollMath.quoteTicket(wager.stake);
        if (exposure != wager.exposure) revert InvalidConfiguration();

        delete _pendingWagers[pendingId];
        uint64 ticketId = ++ticketCount;
        _tickets[ticketId] = Ticket({
            player: wager.player, stake: wager.stake, grossPayout: grossPayout.toUint128(), status: TicketStatus.Open
        });
        emit TicketCreated(ticketId, wager.player, zeroForOne, grossQuote, wager.stake, grossPayout, exposure);
        if (ticketCount == MAX_TICKETS) _closeGame();
    }

    function _accrueProgrammableFee(address sender, uint256 grossQuote, uint256 fee) private {
        if (fee != 0) {
            _programmableLiability[canonicalPoolId][address(0)][PROGRAMMABLE_FEE_OWNER] += fee;
            totalProgrammableFeesAccrued += fee;
            Currency.wrap(address(0)).take(poolManager, address(this), fee, true);
        }
        emit ProgrammableFeeAccrued(canonicalPoolId, PROGRAMMABLE_FEE_OWNER, sender, grossQuote, fee);
    }

    function _closeGame() private {
        state = GameState.Closed;
        closedAtBlock = block.number.toUint64();
        emit GameClosed(closedAtBlock, ticketCount);
    }

    function _requireCanonicalPool(PoolKey calldata key) private view {
        if (!canonicalPoolRegistered || PoolId.unwrap(key.toId()) != canonicalPoolId) revert InvalidPoolKey();
        _validatePoolShape(key);
    }

    function _validatePoolShape(PoolKey calldata key) private view {
        if (address(key.hooks) != address(this)) revert InvalidHookAddress(address(key.hooks));
        if (Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) != launchedToken) {
            revert InvalidPoolKey();
        }
        if (key.fee != 0) revert InvalidLpFee(key.fee);
        if (
            key.tickSpacing != 200 || key.tickSpacing < TickMath.MIN_TICK_SPACING
                || key.tickSpacing > TickMath.MAX_TICK_SPACING
        ) {
            revert InvalidTickSpacing(key.tickSpacing);
        }
    }

    function _assertWethSolvency() private view {
        uint256 accounted = accountedWeth();
        uint256 balance = weth.balanceOf(address(this));
        if (balance < accounted) revert BalanceInvariantViolation(balance, accounted);
        if (reservedExposure > bankrollAssets || reservedExposure > BankrollMath.utilizationLimit(bankrollAssets)) {
            revert BalanceInvariantViolation(reservedExposure, bankrollAssets);
        }
    }
}
