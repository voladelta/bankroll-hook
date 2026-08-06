#!/usr/bin/env node

import fs from "node:fs";

const path = new URL("../submissions/bankroll-hook/submission.json", import.meta.url);
const submission = JSON.parse(fs.readFileSync(path, "utf8"));

const sources = [
  "src/bankroll/BankrollHook.sol",
  "src/bankroll/BankrollHookFactory.sol",
  "src/bankroll/BankrollLaunchV1.sol",
  "src/bankroll/BankrollRouter.sol",
  "src/bankroll/PermanentPositionLocker.sol",
  "src/bankroll/interfaces/IBankrollHook.sol",
  "src/bankroll/interfaces/IRandomnessAdapter.sol",
  "src/bankroll/libraries/BankrollHookData.sol",
  "src/bankroll/libraries/BankrollMath.sol",
  "src/bankroll/libraries/BytecodeHash.sol",
  "src/bankroll/libraries/ProgrammableFeeMath.sol",
  "src/bankroll/randomness/ChainlinkVrfV25Adapter.sol",
  "src/bankroll/types/BankrollTypes.sol",
];
const tests = [
  "test/bankroll/BankrollLaunchV1.t.sol",
  "test/bankroll/BankrollLifecycle.t.sol",
  "test/bankroll/helpers/MockVrfWrapper.sol",
  "test/bankroll/invariant/BankrollSolvency.invariant.t.sol",
  "test/bankroll/unit/BankrollMath.t.sol",
  "test/bankroll/unit/ChainlinkVrfV25Adapter.t.sol",
  "test/bankroll/unit/HookData.t.sol",
  "test/bankroll/unit/ProgrammableFeeMath.t.sol",
  "test/fork/BankrollEthereum.fork.t.sol",
  "script/check-launch-specification.mjs",
];
const modes = [
  "zeroForOne-exactInput",
  "zeroForOne-exactOutput",
  "oneForZero-exactInput",
  "oneForZero-exactOutput",
];

submission.stage = "proposal";
submission.model = {
  id: "bankroll-hook",
  name: "Bankroll Hook",
  summary: "A finite Uniswap v4 launch game where a trader may attach one fixed-odds WETH wager to a successful exact-input swap while a separate WETH bankroll reserves the maximum loss.",
  userOutcome: "Traders keep ordinary four-mode swaps and may use one explicit router for a wagered exact-input swap; bankroll providers fund bounded exposure and redeem the remaining bankroll after finalisation.",
  category: "gaming",
  whyV4: "One canonical hook can authenticate successful pool execution, charge executed gross native quote volume and create a ticket from the same atomic swap result.",
};
submission.builder = {
  github: "voladelta",
  contact: "https://github.com/voladelta",
  beneficiary: null,
  licenseDeclaration: "MIT for first-party source, tests and documents; pinned dependencies retain their own licences.",
};
submission.publicMetadata.project = {
  name: "Bankroll Hook",
  description: "Optional fixed-odds WETH wagers backed by a separately funded bankroll on one canonical Uniswap v4 launch pool.",
  projectUri: "https://github.com/voladelta/bankroll-hook",
  logoUri: null,
  logoContentHash: null,
  metadataMutable: false,
  metadataOwner: null,
};
submission.publicMetadata.token = {
  name: "Bankroll Launch Token",
  symbol: "BANK",
  metadataUri: null,
  metadataContentHash: null,
  logoUri: null,
  logoContentHash: null,
  metadataMutable: false,
  metadataOwner: null,
};
submission.publicMetadata.claimedAffiliations = [
  { organization: "Uniswap v4", relationship: "technology-use", evidenceUri: null },
  { organization: "Chainlink VRF", relationship: "technology-use", evidenceUri: null },
];
submission.assets[1].initialSupply = "1000000000000000000000000000";
submission.target.dependencyBaseline = "model-specific-pinned";

const lifecycle = (actor, valueFlow, custody, failure, event) => ({
  applicable: true,
  actor,
  valueFlow,
  custody,
  failure,
  event,
  notApplicableReason: null,
});
submission.launchLifecycle.tokenCreation = lifecycle(
  "BankrollLaunchV1 creates one fixed one-billion-token UERC20 through its immutable factory.",
  "The launcher sends the supply into one-sided liquidity and sends deliberate dust to the permanent locker.",
  "The launcher and hook hold no initial token supply after launch.",
  "A factory failure, unexpected token address or transfer failure reverts the complete launch.",
  "BankrollTokenLaunched.",
);
submission.launchLifecycle.poolInitialization = lifecycle(
  "The immutable registrar initializes one factory-deployed and router-bound hook.",
  "No game value moves; the hook records the canonical PoolId and opens Funding.",
  "No custody changes at initialization.",
  "Wrong registrar, PoolKey, permission mask or missing router binding reverts.",
  "HookDeployed and FundingOpened.",
);
submission.launchLifecycle.liquidityFormation = lifecycle(
  "BankrollLaunchV1 creates one one-sided v4 position through its immutable PositionManager.",
  "The launched supply enters one locked position.",
  "A dedicated immutable locker owns the position NFT and token dust. It has no transfer, decrease, rescue or admin path.",
  "Any initialization, mint, settlement or custody failure reverts the complete launch.",
  "BankrollLiquidityConfigured.",
);
submission.launchLifecycle.initialTransaction = lifecycle(
  "The creator may execute one declared ETH buy through BankrollLaunchV1 with empty hook data and a minimum token output.",
  "The ordinary swap pays the 10 bps fee and creates no ticket.",
  "PoolManager settles the swap; the hook retains only the fee claim.",
  "Any swap or minimum-output failure must revert the complete launch.",
  "BankrollInitialBuy and ProgrammableFeeAccrued.",
);
submission.launchLifecycle.trading = lifecycle(
  "Traders use ordinary routers for ordinary swaps or the immutable narrow router for an exact-input wager.",
  "PoolManager settles the swap; a wager also moves WETH into an open stake liability.",
  "The hook holds bankroll and stake WETH plus native fee claims.",
  "Slippage, malformed data, capacity or solvency failure reverts atomically.",
  "ProgrammableFeeAccrued, WagerStaged and TicketCreated.",
);
submission.launchLifecycle.feesAndClaims = lifecycle(
  "Callbacks accrue fees and only the immutable Programmable owner may claim.",
  "Ten bps of executed gross native quote moves into an owner liability and later to its selected destination.",
  "The hook holds equal native PoolManager claims.",
  "Unauthorized, empty, zero-recipient or failed claims revert.",
  "ProgrammableFeeAccrued and ProgrammableFeesClaimed.",
);
submission.launchLifecycle.dependencyFailure = lifecycle(
  "Any caller may use the published timeout paths when randomness is not final.",
  "Unfulfilled randomness turns each open stake into a refund liability.",
  "Existing WETH liabilities remain in the hook.",
  "PoolManager failures revert; the official launcher runtime profile remains blocked.",
  "RandomnessExpired.",
);
submission.launchLifecycle.retirement = lifecycle(
  "Anyone may finalise after settlement or expiry.",
  "Players claim first-class liabilities and bankroll providers redeem remaining assets pro rata.",
  "The hook has no administrator or migration path.",
  "A new model requires a new PoolKey.",
  "GameFinalized, TicketClaimed and BankrollRedeemed.",
);

submission.pool.tickSpacing = 200;
submission.pool.lpFee = {
  classification: "lp-fee",
  mode: "static",
  hundredthsOfBip: 0,
  initialHundredthsOfBip: null,
  initializationPath: null,
  applicationMode: null,
  overrideFlagPolicy: null,
  persistentUpdateActor: null,
  persistentUpdateCallSites: [],
  rateLimit: null,
  updatePath: null,
  minimum: null,
  maximum: null,
  inputMetric: null,
  referenceAsset: null,
  measurementUnit: null,
  observationMode: null,
  observationWindow: null,
  curve: null,
  updateCadence: null,
  liquidityDecreaseBehavior: null,
  manipulationResistance: null,
  failureRule: null,
  recipient: "pool-liquidity-providers",
};

const pfee = submission.programmableFee;
pfee.rates.selectedHundredthsOfBip = 0;
pfee.rates.effectiveHundredthsOfBip = 1000;
pfee.rates.projectHundredthsOfBip = 0;
pfee.collection.status = "implemented";
pfee.collection.supportedSwapModes = modes;
pfee.collection.swapModePaths = {
  zeroForOneExactInput: "before-swap-return-delta",
  zeroForOneExactOutput: "after-swap-return-delta",
  oneForZeroExactInput: "after-swap-return-delta",
  oneForZeroExactOutput: "before-swap-return-delta",
};
pfee.accounting.valueFlowId = "programmable-volume-fee";
pfee.accounting.collectionEvent = "ProgrammableFeeAccrued";
pfee.accounting.claimEvent = "ProgrammableFeesClaimed";
pfee.evidence.sourcePaths = ["src/bankroll/BankrollHook.sol", "src/bankroll/libraries/ProgrammableFeeMath.sol"];
pfee.evidence.testPaths = ["test/bankroll/BankrollLifecycle.t.sol", "test/bankroll/unit/ProgrammableFeeMath.t.sol"];

const hook = submission.hook;
hook.used = true;
hook.base = "OpenZeppelin BaseHook with project-specific fee, bankroll and ticket accounting";
hook.upgradeable = false;
hook.sharedAcrossPools = false;
hook.poolNamespace = "One deployment accepts one native ETH and launched-token PoolId.";
hook.poolAdmission = {
  enforcement: "Only the immutable registrar may initialize the exact PoolKey after router binding.",
  factoryOrRegistry: "BankrollHookFactory validates CREATE2 flags and deployed immutable bindings.",
  alternativePoolBehavior: "Alternative pools do not inherit the fee or game and are rejected by this hook.",
  rejectionRule: "Reject a wrong PoolManager caller, hook address, currency order, token, fee, tick spacing or PoolId.",
};
hook.permissions = {
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
  afterRemoveLiquidityReturnDelta: false,
};
hook.callbackPolicies = [
  { callback: "beforeInitialize", necessity: "Authenticate registrar, PoolKey and router binding.", allowedReverts: "Wrong sender, shape or repeated initialization.", userExitImpact: "Runs before any game or LP exit.", noSelfCallImpact: "The callback starts no nested action." },
  { callback: "afterInitialize", necessity: "Record PoolId and open Funding.", allowedReverts: "Wrong sender, PoolId or repeated transition.", userExitImpact: "Runs once before Funding.", noSelfCallImpact: "The callback starts no nested action." },
  { callback: "beforeSwap", necessity: "Validate wager data and collect specified-quote fees.", allowedReverts: "Wrong pool, malformed wager, exact-output wager or arithmetic failure.", userExitImpact: "Does not govern liquidity removal or WETH claims.", noSelfCallImpact: "The hook exposes no swap function." },
  { callback: "afterSwap", necessity: "Collect unspecified-quote fees and create a ticket from executed volume.", allowedReverts: "Partial game fill, volume cap or settlement failure.", userExitImpact: "Does not govern liquidity removal or WETH claims.", noSelfCallImpact: "The hook exposes no swap function." },
];
hook.hookData = {
  used: true,
  schema: "abi.encode(uint8 version=1, bytes32 pendingId), exact length 64",
  identitySource: "none",
  trustedRouterDeploymentRecordId: null,
  callbackSenderRule: "pool-manager-callback-and-exact-router-binding",
  validation: "Hook data carries no user identity. Check the immutable router sender, exact-input mode, version, length, previously staged pending id, same block, Active state and deadline.",
};
const feePart = (basis, formula) => ({
  currency: "currency0",
  basis,
  formula,
  rounding: "down",
  maximumHundredthsOfBip: 1000,
});
hook.feeMechanism = {
  used: true,
  classification: "hook-owned-fee",
  chargedCurrency: "Native ETH currency0 in all four quadrants.",
  swapQuadrants: {
    zeroForOneExactInput: feePart("gross-input", "beforeSwap charges floor((gross*1000+carriedRemainder)/1000000)"),
    zeroForOneExactOutput: feePart("gross-input", "afterSwap gross-ups executed net native input using the carried remainder"),
    oneForZeroExactInput: feePart("gross-output", "afterSwap deducts floor((gross*1000+carriedRemainder)/1000000)"),
    oneForZeroExactOutput: feePart("gross-output", "beforeSwap gross-ups so gross minus cumulative fee equals requested net output"),
  },
  maximumHundredthsOfBip: 1000,
  collectionPath: "quadrant-dependent-swap-return-delta",
  collectionValueFlowId: "programmable-volume-fee",
  liabilityKeyDimensions: ["poolId", "currency", "beneficiary"],
  collectionEvent: "ProgrammableFeeAccrued",
  recipients: [{ role: "programmable-platform", sharePpm: 1000000, addressSource: "fixed-address", address: "0x4957f49620AFf3Adbbe8195a4f633E49cc93376c", binding: "exact-address", derivationRule: null, mutable: false, mutationController: "none", newAddressValidation: "none", mutationEvent: null }],
  ownership: "The immutable Programmable owner receives the complete fee; project share is zero.",
  claimPolicy: "Only the immutable owner may claim anytime to a nonzero destination selected for that claim.",
};
hook.customAccounting = {
  used: true,
  backingSource: "WETH balance backs game liabilities; native PoolManager claims back the fee liability.",
  conservationEquation: "WETH balance >= bankrollAssets + openStakeLiability + playerClaimLiability; native claim balance backs the fee liability.",
  settlement: "Every PoolManager unlock settles its final deltas; WETH state changes and transfers are atomic.",
  partialFillBehavior: "Ordinary unspecified-quote paths use executed deltas; specified-quote and game paths reject unsupported partial fills.",
  liabilityNamespace: "Canonical PoolId plus asset and beneficiary where applicable.",
  liabilityKeyDimensions: ["poolId", "currency", "beneficiary"],
  crossPoolNetting: false,
  duplicateCurrencyPolicy: "One hook accepts one PoolId.",
  failureIsolation: "Any accounting mismatch reverts the complete action.",
  withdrawalOrdering: "Update liability before external transfer, guarded by transient reentrancy protection.",
};
const zeroDelta = {
  mode: "zero-only",
  formula: null,
  minimum: "0",
  maximum: "0",
  minimumSign: "zero",
  maximumSign: "zero",
  positiveSettlementActions: [],
  negativeSettlementActions: [],
};
const positiveDelta = (currency) => ({
  mode: "positive-only",
  formula: "floor((executed gross native quote * 1000 + carried remainder) / 1000000)",
  minimum: "zero for an individual swap only when the carried cumulative numerator has not reached one quote unit",
  maximum: "strictly less than the executed gross native quote",
  minimumSign: "zero",
  maximumSign: "positive",
  positiveSettlementActions: [{ order: 1, actor: "hook", operation: "take", currency, assetKind: "native", deltaOwner: "hook", deltaEffect: "negative", counterparty: "hook", authorizationRule: "authenticated PoolManager callback", msgValueRule: null, amountRule: "Mint exactly the fee as native ERC-6909 claims to the hook.", completionDeadline: "before-hook-return" }],
  negativeSettlementActions: [],
});
const quadrant = (specifiedCurrency, unspecifiedCurrency, amountSign, beforeFee) => ({
  supported: true,
  specifiedCurrency,
  unspecifiedCurrency,
  amountSign,
  specifiedComponent: beforeFee ? positiveDelta("specified") : zeroDelta,
  unspecifiedComponent: zeroDelta,
  residualAmmEquation: "amountSpecified-plus-specifiedDelta",
  finalCallerDeltaEquation: "pool-manager-swap-delta-minus-hook-delta",
  specifiedDeltaCanConsumeEntireAmount: false,
  rounding: "Carry the lifetime numerator remainder by canonical PoolId, native currency and immutable owner.",
  zeroAmmLeg: "forbidden",
  partialFillRule: beforeFee ? "afterSwap checks the expected specified native amount and reverts a mismatch." : "afterSwap uses the actual executed native BalanceDelta.",
  slippageInvariant: "The external router checks the final caller delta after the hook return delta.",
  failureRule: "Any sign, bound, cast, partial-fill or claim-mint mismatch reverts atomically.",
});
hook.returnDeltaAccounting = {
  used: true,
  quadrants: {
    zeroForOneExactInput: quadrant("currency0", "currency1", "negative-exact-input", true),
    zeroForOneExactOutput: quadrant("currency1", "currency0", "positive-exact-output", false),
    oneForZeroExactInput: quadrant("currency1", "currency0", "negative-exact-input", false),
    oneForZeroExactOutput: quadrant("currency0", "currency1", "positive-exact-output", true),
  },
  executionEvent: "ProgrammableFeeAccrued",
};
hook.postReturnDeltaAccounting.afterSwap.used = true;
hook.postReturnDeltaAccounting.afterSwap.returnedDeltaShape = "unspecified-currency-int128";
hook.postReturnDeltaAccounting.afterSwap.positiveMeaning = "hook-credit-caller-debit";
hook.postReturnDeltaAccounting.afterSwap.negativeMeaning = "hook-debt-caller-credit";
hook.postReturnDeltaAccounting.afterSwap.backingSource = "Equal native ERC-6909 claims minted before return.";
hook.postReturnDeltaAccounting.afterSwap.callerDeltaEquation = "protocol-delta-minus-hook-delta";
hook.postReturnDeltaAccounting.afterSwap.componentPolicies = { unspecified: positiveDelta("unspecified"), currency0: null, currency1: null };
hook.postReturnDeltaAccounting.afterSwap.bounds =
  "Zero or floor((executed gross native quote * 1000 + carried remainder) / 1000000), checked to int128.";
hook.postReturnDeltaAccounting.afterSwap.rounding =
  "Carry the lifetime numerator remainder by canonical PoolId, native currency and immutable owner.";
hook.postReturnDeltaAccounting.afterSwap.slippageOrMinimums = "The router checks the final caller delta.";
hook.postReturnDeltaAccounting.afterSwap.failureRule = "Cast, claim mint or ledger failure reverts the swap.";
hook.postReturnDeltaAccounting.afterSwap.executionEvent = "ProgrammableFeeAccrued";
hook.postReturnDeltaAccounting.afterAddLiquidity.used = false;
hook.postReturnDeltaAccounting.afterRemoveLiquidity.used = false;
hook.erc6909Claims = {
  used: true,
  currencyIdDerivation: "currency-address-uint160",
  claimBalanceScope: "claim-owner-and-currency",
  poolIdIncludedInClaimId: false,
  owner: "The hook owns claims backing the immutable owner liability.",
  operatorPolicy: "No external operator.",
  mintFlow: "take(..., claims=true) during fee collection",
  burnFlow: "settle(..., burn=true) during claim",
  takeSettleFlow: "Mint in the swap unlock; burn then take native ETH in a claim unlock.",
  liabilityKeys: "canonical PoolId, native currency and owner",
  liabilityKeyDimensions: ["poolId", "currency", "beneficiary"],
  crossPoolNetting: false,
  transferPolicy: "No claim transfer function is exposed.",
  redemption: "Immutable owner only, to its selected destination.",
  roundingDust: "The numerator remainder is carried for the canonical pool lifetime and is not cleared by claims.",
  aggregateSolvencyEquation: "native claim balance >= programmable liability",
};
hook.nestedActions = {
  used: false,
  directPoolManagerCalls: false,
  routerCalls: false,
  allowedActions: [],
  samePoolPolicy: "The hook exposes no swap function.",
  crossPoolPolicy: "No other pool is accepted.",
  callbackSuppression: "Fee claim unlock performs settle and take only.",
  directCallbackBehavior: "self-call-hook-callbacks-skipped",
  routerCallbackBehavior: "hook-callbacks-can-reenter",
  maximumDepth: 1,
  stateCommitOrder: "Validate, account, settle, then emit; any later revert rolls back all writes.",
  transientDeltaOwner: "The hook for claims and the router for game swaps.",
  syncInterleaving: "Claims use ERC-6909 mint and burn without ERC-20 sync.",
  slippageAggregation: "The router checks final output after hook deltas.",
  failureAtomicity: "Any failure reverts the complete transaction.",
};

submission.valueFlows = [
  { id: "core-swap", action: "execute the canonical v4 swap", asset: "native ETH and launched token", from: "trader and pool", to: "pool and trader", amountRule: "Final PoolManager delta after the fixed zero LP fee and hook fee.", settlement: "The calling router settles all deltas before unlock completion.", failure: "Any callback, slippage or settlement failure reverts." },
  { id: "programmable-volume-fee", action: "accrue the mandatory charge", asset: "native ETH", from: "executed gross quote volume", to: "immutable owner liability", amountRule: "floor(gross quote * 1000 / 1000000), project share zero.", settlement: "Return delta plus equal native ERC-6909 claims.", failure: "Any mismatch reverts the swap." },
  { id: "wager", action: "stage and create one ticket", asset: "WETH", from: "player", to: "open stake liability", amountRule: "Immutable stake within volume and bankroll caps.", settlement: "Router transfer before unlock and ticket creation after successful swap.", failure: "Any failure reverts stake, swap and pending state." },
  { id: "bankroll", action: "fund and redeem the game bankroll", asset: "WETH", from: "bankroll provider", to: "hook then provider", amountRule: "One share per WETH in Funding and pro-rata remaining assets at exit.", settlement: "SafeERC20 transfer with internal share ledger.", failure: "Invalid state, amount or solvency reverts." },
  { id: "ticket-claim", action: "pay a win or timeout refund", asset: "WETH", from: "player liability", to: "ticket player", amountRule: "1.96x stake for a win or stake for timeout.", settlement: "Mark claimed, reduce liability and transfer atomically.", failure: "Wrong player or state and repeated claim revert." },
];
submission.authorities = [
  { role: "Programmable fee owner", controller: "0x4957f49620AFf3Adbbe8195a4f633E49cc93376c", capabilities: ["claim its accrued fee to a selected destination"], mutable: false, delay: "no-delay-immutable", userExitImpact: "Cannot touch bankroll, tickets, swaps or LP positions." },
  { role: "Immutable registrar", controller: "BankrollLaunchV1 address supplied at construction", capabilities: ["initialize the one canonical pool"], mutable: false, delay: "no-delay-one-time", userExitImpact: "Acts once before Funding and has no later control." },
  { role: "No mutable model administrator", controller: "none", capabilities: ["No party can pause, replace contract code, rescue, change game economics or replace immutable dependencies."], mutable: false, delay: "not-applicable", userExitImpact: "Permissionless deadline and claim paths remain available without an administrator." },
];

for (const capability of Object.values(submission.capabilities)) capability.used = false;
submission.capabilities.externalCalls = {
  used: true,
  targets: ["Uniswap v4 PoolManager", "Uniswap v4 PositionManager", "UERC20 factory", "WETH", "Chainlink VRF v2.5 wrapper"],
  callSites: ["BankrollLaunchV1 token, pool, position and initial-buy flow", "BankrollHook claim and WETH flows", "BankrollRouter unlock", "PermanentPositionLocker fee collection", "ChainlinkVrfV25Adapter request"],
  reentrancyPolicy: "Transient reentrancy guards on value-moving public paths; authenticated callbacks remain available only to their immutable callers.",
  stateDriftPolicy: "Immutable dependencies and atomic state transitions; request quote has caller maximum and exact payment.",
  returnValuePolicy: "Decode and validate PoolManager unlocks; SafeERC20 checks token calls; Chainlink base handles wrapper calls.",
  failureAtomicity: "External failure reverts the complete action except a later permissionless randomness timeout.",
};
submission.capabilities.externalLiquidity = {
  used: true,
  custody: "The hook holds WETH bankroll and liabilities, not an external yield position.",
  ownership: "Internal non-transferable shares own the residual bankroll pro rata.",
  shareAccounting: "One share per WETH deposit during Funding; pro-rata redemption after finalisation.",
  solvencyEquation: "WETH balance >= bankroll assets + open stakes + player claims.",
  lossAllocation: "Winning exposure reduces bankroll assets; losing stakes increase them.",
  donationPolicy: "Direct donations mint no shares and do not increase recorded assets.",
  exitPath: "Funding withdrawal or terminal redemption.",
  dependencyFailure: "A failed WETH transfer reverts without changing final accounting.",
};

submission.integration.swapModes = modes;
submission.integration.routerGeneration = null;
submission.integration.partialFills = "Ordinary unspecified-quote modes charge executed deltas; wager partial fills and specified-quote mismatches revert.";
submission.integration.slippage = "Ordinary routers enforce their settings; the wager router enforces minimum output and a price limit; the atomic launcher binds minimumInitialBuyTokenAmount.";
submission.integration.deadline = "The wager router rejects calls after the user-supplied timestamp.";
submission.integration.permit2 = "Not used by the wager router; token input uses a direct ERC-20 allowance.";
submission.integration.stateReads = "Read game, ticket, liability and bankroll state from the hook and randomness status from the adapter.";
submission.integration.events = ["BankrollTokenLaunched", "BankrollLiquidityConfigured", "BankrollInitialBuy", "PositionFeesCollected", "HookDeployed", "FundingOpened", "GameActivated", "WagerStaged", "TicketCreated", "RandomnessRequested", "RandomnessConsumed", "RandomnessExpired", "TicketSettled", "TicketClaimed", "GameFinalized", "BankrollRedeemed", "ProgrammableFeeAccrued", "ProgrammableFeesClaimed"];
submission.integration.appSourcePaths = [];
submission.integration.integrationTestPaths = [];
submission.integration.routingAndDiscoverability = {
  routingMode: "not-planned",
  allowlistTriggers: { usesDeltaFlag: true, addressStartsWith91: false, targetsMajorPair: false, permissionedPool: false },
  uniswapRoutingStatus: "not-applicable",
  hookRegistryStatus: "not-submitted",
  customHookDataRequired: false,
  standardRouterCompatible: true,
  permissionedRouting: { required: false, minimumRouterGeneration: null, adapterCurrencyUsed: null, allowedWrapperBindings: null, positionManagerBinding: null, routingAllowlistRequiredPerChain: null },
  sourcePaths: [],
  testPaths: [],
};
submission.integration.dataReconstruction = {
  mode: "events-with-confirmed-reads",
  eventCoverage: "Hook events cover game, ticket, fee and claim transitions; confirmed reads reconcile aggregate liabilities and state.",
  cursor: "block-number-transaction-index-log-index",
  startBlockPolicy: "Start at HookDeployed for the exact chain and hook.",
  finalityDepth: 12,
  reorgPolicy: "Roll back to the last finalized cursor and replay before publishing state.",
  backfillPolicy: "Replay every hook event from deployment.",
  checkpointPolicy: "Checkpoint game state, ticket count, bankroll and liabilities at finalized blocks.",
  freshnessTargetSeconds: 60,
  staleAfterSeconds: 300,
  freshnessMeasurement: "Wall-clock lag from chain head to the last indexed finalized block.",
  reconciliation: "Compare indexed aggregates with confirmed hook getters and PoolManager native claim balance.",
  reserveReconstruction: { used: true, balanceSources: ["Hook WETH balance", "Hook native PoolManager claim balance"], liabilitySources: ["Hook bankroll, open stake, player claim and programmable liability getters"], attributionKeys: ["chainId", "poolId", "currency", "beneficiary"], solvencyEquation: "WETH balance covers WETH ledgers and native claims cover the fee liability.", poolLiquidityTreatment: "excluded-from-hook-reserves", donationAndDustPolicy: "Direct donations create no shares or liabilities.", reconciliation: "Withhold data and alert on any confirmed mismatch." },
  sourcePaths: ["src/bankroll/BankrollHook.sol"],
  testPaths: ["test/bankroll/BankrollLifecycle.t.sol", "test/bankroll/invariant/BankrollSolvency.invariant.t.sol"],
};
submission.integration.platformHandoff = {
  intended: true,
  websiteRegistryPath: null,
  uiSourcePaths: [],
  apiSourcePaths: [],
  indexerSourcePaths: [],
  testPaths: [],
  reviewStatus: "not-requested",
  maintainerReviewRequired: true,
  selfApproval: false,
  availabilityClaimed: false,
  handoffNotes: "The repository includes an offchain React review demo, but this proposal does not claim it as a reviewed or routed product client. It does not include a production API, indexer, routing registration, monitoring or deployment. Maintainers must review the client and exact deployment bindings before any product integration.",
};

submission.implementation = {
  sourcePaths: sources,
  testPaths: tests,
  compilerBuildInfoPaths: [],
  specificationPath: "submissions/bankroll-hook/launch.json",
  testEvidencePath: "submissions/bankroll-hook/EVIDENCE.md",
  dependencyLockPath: "submissions/bankroll-hook/dependency-lock.json",
  gateStatusPath: null,
  reviewTargetPath: null,
  runtimeAssetManifestPath: null,
};
submission.risk = {
  dimensions: { complexity: 3, customMath: 2, externalDependencies: 3, externalLiquidity: 3, valueAtRisk: 3, teamMaturity: 2, upgradeability: 0, autonomy: 2, priceImpact: 1 },
  rationales: {
    complexity: "Four fee quadrants, transient PoolManager accounting and a finite asynchronous game interact.",
    customMath: "Payout, utilisation, exact-output gross-up and pro-rata redemption are small and fuzzed.",
    externalDependencies: "PoolManager, PositionManager, UERC20 factory, WETH and Chainlink VRF are immutable runtime dependencies.",
    externalLiquidity: "The hook holds a separately funded bankroll and player liabilities.",
    valueAtRisk: "Bankroll, stakes, payouts and fee claims remain in the hook until exit.",
    teamMaturity: "No independent review or production deployment evidence exists yet; local and pinned-fork evidence remains builder-declared and untrusted.",
    upgradeability: "There is no upgrade or mutable admin path.",
    autonomy: "Permissionless callers progress deadlines, randomness and bounded settlement.",
    priceImpact: "The hook charges 10 bps but does not change the LP curve or fee.",
  },
  declaredTotal: 19,
  declaredTier: "high",
  featureTriggers: ["autonomous", "custom-accounting", "custom-math", "external-calls", "external-liquidity", "hook-held-liquidity", "price-impact", "return-delta"],
};
submission.operations.monitoring = "Reconcile confirmed WETH balances, native claims, bankroll, ticket and fee liabilities; alert on mismatches, stale randomness and stalled settlement.";
submission.operations.incidentResponse = "There is no pause or upgrade. Publish the affected chain, hook, PoolId and block, stop product routing, preserve player exits and require a new reviewed hook for code changes.";
submission.disclosures = [
  "Local prototype only: not audited, accepted, deployed, verified, routed, monitored or available.",
  "The launch flow has local and pinned historical Ethereum-fork evidence; this is not production deployment or monitoring evidence.",
  "Selected Ethereum dependency runtimes are pinned in submissions/bankroll-hook/dependency-evidence.json; the official PoolManager and PositionManager source refs remain non-immutable in the current registry.",
  "A wager has equal win and loss probability, pays 1.96x gross on a win and has a 2% expected house edge.",
  "The project fee is zero; the mandatory 10 bps fee belongs only to the immutable Programmable owner.",
  "The custom hook accepts sub-1,000-unit native quote swaps and carries their fee numerator so the reviewer-requested 1,000 x 999 wei regression accrues 999 wei. This differs from the Builder 1.5 standard profile, which rejects positive gross quote amounts below 1,000 units, and remains an explicit architecture-review item.",
];
submission.noHookArchitecture = null;
submission.unresolved = [];

fs.writeFileSync(path, `${JSON.stringify(submission, null, 2)}\n`);
