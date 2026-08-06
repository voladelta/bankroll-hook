# Bankroll Hook evidence

Evidence date: 7 August 2026

Evidence state: candidate working-tree evidence; the public application package must be regenerated after this exact source is committed and pushed

## Compatibility

The implementation uses one custom hook because wager admission and the mandatory fee both need atomic PoolManager execution. The hook integrates the 10 bps Programmable fee directly.

The canonical projection is pinned to Programmable Builder release `v0.4.0`, commit `5b47504299c5dbe0ab694be8d163e80d352c8166`, tree `69e01dfcb883e60390fc8869271b6aff03fc67bf`, submission standard `1.5.0` and fee policy `1.1.0`. Its deterministic report has one explicit blocker: the standard profile requires a positive gross quote below 1,000 units to revert, while the immutable review request requires 999-wei swaps to remain successful and accrue cumulatively. The source follows the review request. `submission.v1.5.json` and `compatibility-report.v1.5.json` disclose that exception and do not claim standard-profile conformance.

The production intake still validates the legacy `1.3.0` projection. Its regenerated compatibility report says `PROTOTYPE_READY` with no deterministic blockers. Both reports bind hook mask `0x30cc` and retain warnings for return-delta specialist review, the novel game architecture and deterministic Solidity import closure. The legacy projection is packaging compatibility only; the canonical design record is 1.5.

The Builder package check passed proposal structure. A new application package must be generated only after this candidate becomes a clean public source commit; that package must record the exact source commit, source tree, submission hash and review-target hash. The application stage remains proposal.

The Builder 1.5 official Ethereum records still leave PoolManager and PositionManager source refs unresolved and require runtime verification before execution. This submission therefore binds its selected dependencies independently at a pinned historical block, adds a current-head runtime smoke and makes no production deployment or availability claim.

## Local results

| Check | Result | Scope |
| --- | --- | --- |
| `npm test` | 76 tests passed, no failures | unit, 512-run fuzz, adversarial lifecycle, launch integration, VRF boundaries and stateful invariants; fork tests excluded explicitly |
| `MAINNET_RPC_URL=<archive-rpc> npm run test:fork` | 2 tests passed, no failures | Ethereum block 25,690,000 dependency identity, interfaces and full launch lifecycle |
| Current-head Ethereum smoke | passed at block 25,697,510 | five runtime hashes, PositionManager binding, VRF version, nonzero quote and wrapper native balance |
| `forge lint` | passed with no findings | first-party Solidity |
| `npm run build` | passed | first-party runtime and init code below their protocol limits |
| `npm run launch:check` | passed | exact compiler profile, compiled constructor ABIs, source hashes, dependency addresses, target order, internal children and launch graph |
| `bun run lint` in `demo` | passed | React, wagmi and Zustand source |
| `bun run build` in `demo` | passed | TypeScript and Vite production build |
| `uvx --from slither-analyzer slither . --exclude-dependencies` | completed with documented dispositions below | first-party Solidity; Slither 0.11.6 |
| `npm audit --omit=dev` | 25 advisories: 15 low, 5 moderate and 5 high | the pinned dependency tree, largely transitive tooling bundled by Chainlink; no automatic upgrade applied |
| Independent review | not done | local authoring only |

The React demo rendered at the local Vite URL and the supplied desktop screenshot was reviewed. Direct browser automation was unavailable, so no automated click-through or mobile viewport run is claimed.

The 6 invariant properties each ran 128 sequences at depth 48. Foundry made 6,144 handler calls per property with no Foundry-level reverts or discarded calls. The handlers exercised Funding deposits and withdrawals, activation or cancellation, wagered buys and sells, closure, randomness, settlement, claims, Programmable fee claims, finalisation and redemption. The native claim-backing property checks that the hook's PoolManager native balance equals its Programmable fee liability after every action.

The clean size check records 22,650 bytes for `BankrollHook`, 5,563 bytes for `BankrollHookFactory`, 5,316 bytes for `BankrollRouter`, 8,597 bytes for `BankrollRouterFactory`, 18,529 bytes for `BankrollLaunchV1`, 2,182 bytes for `PermanentPositionLocker` and 3,082 bytes for `ChainlinkVrfV25Adapter` at 5,000 optimiser runs. All first-party deployables remain below EIP-170.

Foundry's unfiltered `--sizes` report also includes the pinned Uniswap `PositionDescriptor`, which is 29,387 bytes in this build profile and makes that unfiltered command return a dependency size error. The project build uses a first-party size gate so it does not hide or confuse that upstream result with this project's deployables.

## Static-analysis dispositions

Slither 0.11.6 completed on the exact working source with `--exclude-dependencies` and returned a nonzero status with 37 raw results across 16 detector categories. This evidence does not describe that run as zero-findings or as an audit.

- The randomness request, consume and expiry entry points share OpenZeppelin's transient reentrancy guard. A regression test makes the adapter attempt expiry reentrancy during both external calls and proves both attempts fail.
- PoolManager settlement calls occur inside authenticated v4 callback or unlock contexts. The hook verifies its immutable manager and canonical PoolKey; the launcher and wager router are separately guarded.
- The arbitrary-send and low-level-call results are the wager router's explicit user-selected native recipient. The router rejects a zero recipient, uses a user deadline, is reentrancy-guarded and reverts the whole swap when delivery fails.
- Strict-equality results are enum-state checks and the specified random-bit win rule. Timestamp use is the caller-selected transaction deadline.
- External and costly loop results are bounded by the immutable settlement maximum of 16. The balance call is part of the post-settlement solvency assertion.
- The two unused returns deliberately discard the ticket gross payout when only exposure is needed and position data when only PoolKey is needed.
- Assembly writes zero only to the 32-byte immutable references emitted in the exact `BankrollHook` and `BankrollRouter` compiler artifacts; the runtime length is checked before every write.
- Mixed pragmas are confined to pinned dependencies. The too-many-digits and unimplemented-BaseHook results are tool false positives for creation-code literals and an implemented `getHookPermissions` override.

Reentrancy ordering around PoolManager internals, the reviewed randomness dependency and the remaining informational results still require maintainer and independent review.

## Implemented fee evidence

Source:

- `src/bankroll/BankrollHook.sol`
- `src/bankroll/libraries/ProgrammableFeeMath.sol`

Tests:

- `test/bankroll/unit/ProgrammableFeeMath.t.sol`
- `test/bankroll/BankrollLifecycle.t.sol`

The integration tests reconcile the exact fee event, gross quote, fee and before/after remainder in ETH-to-token and token-to-ETH exact-input and exact-output modes. Separate regressions execute 1,000 successful 999-wei swaps in both gross and fee-on-top paths and prove the cumulative identities produce 999 wei of fee rather than zero. Claims preserve the carried remainder; recipient failure rolls back the whole claim.

The policy is 10 bps effective, 10 bps platform and zero project. It excludes LP fees. Both the liability and carried numerator remainder are keyed by canonical PoolId, native currency and owner. Donation does not accrue a fee, a specified-quote partial fill rolls back the fee and remainder, and an alternate pool cannot share either state.

## Implemented game evidence

The lifecycle integration test covers a wagered buy, close, direct-funded request through a mock adapter, fulfilment, permissionless pull, settlement and finalisation. It also covers the no-request timeout refund.

A second direction test proves a token-to-ETH exact-input swap can create a ticket from executed native output. Unit tests cover the 1.96x payout, 20% volume cap, 80% utilisation limit and pro-rata redemption formula.

Adversarial tests reject a wrong PoolManager, wrong router, alternate PoolKey, malformed hook data, replayed or stale pending wagers and exact-output wager mode. They also cover stake bounds, insufficient Funding cancellation, zero-ticket finalisation, the 64-ticket capacity and four bounded settlement batches, atomic deadline, price-limit, partial-fill, output-recipient and transfer failures, both randomness timeout paths, repeated fee claims, repeated ticket claims and repeated settlement.

The dedicated adapter tests bind its quote to exact native payment, reject reused wrapper request IDs before request-key overwrite, authenticate wrapper-only fulfilment, reject unknown and duplicate fulfilment and enforce consumer-only one-shot consumption. Hook-level tests enforce the caller's maximum and exact request fee.

The stateful suite checks that WETH covers all game liabilities, reserved exposure stays within both caps, bankroll shares remain conserved, terminal states do not return to Active, no ticket pays twice and native PoolManager claims cover every Programmable fee liability.

## Bytecode binding and launch provenance

The factory accepts init code so CREATE2 salts remain caller-selectable, but it does not accept an alternate implementation. `BankrollHookFactory` requires the exact reviewed hook creation-code length and hash, then checks the constructor-argument suffix against the launch parameters before deployment. `BankrollRouterFactory` constructs the router init code from the reviewed source creation code and checks its creation hash. Both factories check deployed runtime length and an immutable-slot-normalised runtime hash before recording provenance.

The approved values for the reviewed compiler input are:

| Contract | Creation code | Runtime code |
| --- | --- | --- |
| `BankrollHook` | 24,570 bytes; `0xa21f6c45a4a59d1d458fdf3b56c091650c0bd84beed1cd4fe0a25b7d2a27cc83` | 22,650 bytes; `0x0db8456b774bdc7bdd868369ca50beb7cc7eae2802390f8935e21eaa05158387` |
| `BankrollRouter` | 5,949 bytes; `0xe1ce945bbb95bd1dcf9ffc7da4c1585009416599fdb21340768d4020c8e9556d` | 5,316 bytes; `0xef3209b3d091029d17ff449fd871ce3fa8f1dd3aae43f22b3cae1148879e89bf` |

The runtime normaliser clears only the compiler-recorded immutable slots. The raw deployed runtime hash is also stored. `BankrollLaunchV1` independently binds all four reviewed hashes, rejects a factory that reports different values, returns the raw hook and router hashes, includes them in the launch hash and emits `BankrollLaunchProvenance`. Mismatch tests cover modified hook creation bytes, modified constructor arguments, modified deployed runtime bytes and an unreviewed factory hash.

## Implemented launch evidence

Source:

- `src/bankroll/BankrollLaunchV1.sol`
- `src/bankroll/PermanentPositionLocker.sol`
- `src/bankroll/BankrollHookFactory.sol`

Test:

- `test/bankroll/BankrollLaunchV1.t.sol`
- `script/check-launch-specification.mjs`

Launch artifact:

- `submissions/bankroll-hook/launch.json`

The launch artifact declares `BankrollLaunchV1` as its root, with `BankrollRouterFactory`, `BankrollHookFactory` and `ChainlinkVrfV25Adapter` deployed first. Its constructor locators resolve the exact PoolManager, PositionManager, UERC20Factory, WETH and VRF wrapper dependency records plus earlier targets. Its internal-child plans bind the fixed-supply token, mined hook, bound router and permanent position locker, including every address word, the eight launch-time `BankrollConfig` fields, salt derivations and the hook's complete six-permission set. The launch-call record binds the exact ABI signature, selector and initial-buy minimum. The nine-step atomic plan ends with pool initialization, position mint, custody reconciliation and the optional minimum-protected creator buy; every failure reverts the transaction.

The local launch integration test uses real Uniswap v4 PoolManager, PositionManager and Permit2 test deployments with a local deterministic UERC20 factory. The separate pinned Ethereum fork uses the selected production PoolManager, PositionManager, UERC20Factory and WETH runtimes and launches through them at block 25,690,000.

The tests prove the predicted token, mined hook and bound router configuration. They also prove fixed supply, canonical PoolId, launch hash, permanent position-NFT ownership and fee collection, empty launcher and PositionManager token custody, zero and minimum-protected creator buys and mandatory fee accrual. Hostile token factories, invalid mined hooks, modified init code, repeated salts, token collisions and creator-buy slippage all revert. A common assertion proves no token, hook, router, locker, pool slot, position increment or launch record survives each failed launch. The fork test repeats the actual token creation, pool initialization, position mint and permanent custody lifecycle using the pinned Ethereum contracts.

## Dependency records

The npm v3 lock, SHA-256 `72ee6848008260d91430b8aae49851f2602b1fb407fd1bf04fcf9c5c1211c067`, pins OpenZeppelin Contracts 5.5.0, OpenZeppelin Uniswap Hooks 1.1.1, Uniswap v4 Core 1.0.2, Uniswap v4 Periphery 1.0.3 and Chainlink Contracts 1.5.0. Dependencies retain their own licences as recorded in `NOTICE.md` and package metadata.

`npm audit --omit=dev` reports 25 package-level advisories: 15 low, 5 moderate and 5 high, with no critical result. The affected OpenZeppelin 3.x/4.x nodes and JavaScript packages are nested in Chainlink's bundled multi-chain dependency tree; the project's direct OpenZeppelin dependency is 5.5.0. The compiled first-party closure imports Chainlink's VRF v2.5 wrapper consumer, interface and client library, not the reported governor, proxy, Base64, Arbitrum or JavaScript tooling paths. No automatic dependency rewrite was applied because replacing the pinned Chainlink package changes the reviewed source closure and requires a separate compatibility review.

`submissions/bankroll-hook/dependency-evidence.json` records the exact block header, official references, explorer compiler records, bytecode lengths and runtime hashes for the selected Ethereum PoolManager, PositionManager, UERC20Factory, WETH and Chainlink VRF v2.5 wrapper. At block 25,690,000 the test verifies all five runtime hashes, the PositionManager-to-PoolManager binding, VRF wrapper version and callable quote interface, and a real WETH deposit.

The same fork then deploys the reviewed local adapter, factories and launcher and completes UERC20 prediction and creation, CREATE2 hook mining, reviewed hook/router hash enforcement, v4 pool initialization, position minting and permanent position-NFT custody against the selected Ethereum dependencies. The two fork tests were rerun against an archive endpoint and pass. The wrapper returns a zero native request quote in that historical state, so that fork records only the successful typed call.

At Ethereum block 25,697,510, a separate current-head smoke re-read all five runtimes and reproduced every pinned length and hash. PositionManager still returned the selected PoolManager and the wrapper still returned `VRFV2PlusWrapper 1.0.0`. At 179,724,274 wei gas price, its 200,000-gas, one-word native quote was 67,081,801,959,395 wei and its native balance was 23,735,849,938,180,266,047 wei. These are point-in-time operational observations, not funding sufficiency, future availability or monitoring guarantees.

PoolManager and PositionManager retain `official-feed-ref-unresolved` source status after rechecking the Builder 1.5 official records: those records still have null release commits and mutable source URLs. Their exact runtime identities and verified explorer compiler records are pinned here; this submission does not misstate them as reproducible source matches. UERC20Factory is pinned to release commit `de5bacd215f6aae50e524297c18fcf78b69b6312`; Chainlink package source is pinned to `contracts-v1.5.0` commit `86aa5a1d34b20eda8d18fe6eb0e4882948e545ba`.

## Remaining gates

- commit and push this exact source, then regenerate and hash-bind the application package to that public commit
- obtain maintainer re-review and independent review
- resolve the official PoolManager and PositionManager source refs to immutable commits before any claim of reproducible deployed-source matching
- complete deployment, source verification, platform routing, indexer, monitoring and legal gates before production use

No evidence here proves an audit, acceptance, deployment, source verification, routing approval or product availability.
