# Bankroll Hook evidence

Evidence date: 4 August 2026

Evidence state: source evidence for the exact public commit bound by the generated application package

## Compatibility

The implementation uses one custom hook because wager admission and the mandatory fee both need atomic PoolManager execution. The hook integrates the 10 bps Programmable fee directly.

The regenerated local compatibility report says `PROTOTYPE_READY` with no deterministic blockers. The hook mask is `0x30cc`. The report retains warnings for return-delta specialist review, the novel game architecture and deterministic Solidity import closure.

The Builder package check passed proposal structure. The generated application package records the exact public source commit, source tree, submission hash and review-target hash. The application stage remains proposal.

The current Programmable repository is release `programmable-v4-builder-v0.2.1` at commit `0f2a2704216ba3eeb3c9761466aa9197abe927bc`. Its official Ethereum launchpad profile is marked `reference-conflicted-runtime-unverified`. The project therefore makes no mainnet-launch claim.

## Local results

| Check | Result | Scope |
| --- | --- | --- |
| `forge test -vv` | 37 tests passed, no failures | unit, 512-run fuzz, adversarial lifecycle, launch integration and stateful invariants |
| `forge lint` | passed with no findings | first-party Solidity |
| `npm run build` | passed | first-party runtime and init code below their protocol limits |
| `bun run lint` in `demo` | passed | React, wagmi and Zustand source |
| `bun run build` in `demo` | passed | TypeScript and Vite production build |
| Slither | unavailable | tool is not installed |
| `npm audit --omit=dev` | 25 advisories: 15 low, 5 moderate and 5 high | the pinned dependency tree, largely transitive tooling bundled by Chainlink; no automatic upgrade applied |
| Mainnet fork | not run | no RPC or recorded block selected |
| Independent review | not done | local authoring only |

The React demo rendered at the local Vite URL and the supplied desktop screenshot was reviewed. Direct browser automation was unavailable, so no automated click-through or mobile viewport run is claimed.

The 5 invariant properties each ran 128 sequences at depth 48. Foundry made 6,144 handler calls per property with no Foundry-level reverts or discarded calls. The handlers exercised Funding deposits and withdrawals, activation or cancellation, wagered buys and sells, closure, randomness, settlement, claims, finalisation and redemption.

The clean size check recorded 21,978 bytes for `BankrollHook`, 2,636 bytes for `BankrollHookFactory`, 5,316 bytes for `BankrollRouter`, 7,128 bytes for `BankrollRouterFactory`, 16,302 bytes for `BankrollLaunchV1`, 2,182 bytes for `PermanentPositionLocker` and 2,939 bytes for `ChainlinkVrfV25Adapter` at 5,000 optimiser runs.

Foundry's unfiltered `--sizes` report also includes the pinned Uniswap `PositionDescriptor`, which is 29,387 bytes in this build profile and makes that unfiltered command return a dependency size error. The project build uses a first-party size gate so it does not hide or confuse that upstream result with this project's deployables.

## Implemented fee evidence

Source:

- `src/bankroll/BankrollHook.sol`
- `src/bankroll/libraries/ProgrammableFeeMath.sol`

Tests:

- `test/bankroll/unit/ProgrammableFeeMath.t.sol`
- `test/bankroll/BankrollLifecycle.t.sol`

The integration test executes ETH-to-token and token-to-ETH swaps in exact-input and exact-output modes. Each case increases the native fee liability. Another test proves a non-owner cannot claim and the immutable owner can claim the full amount to a selected recipient.

The policy is 10 bps effective, 10 bps platform and zero project. It excludes LP fees. The liability key is canonical PoolId, native currency and owner. There is no cross-pool netting.

## Implemented game evidence

The lifecycle integration test covers a wagered buy, close, direct-funded request through a mock adapter, fulfilment, permissionless pull, settlement and finalisation. It also covers the no-request timeout refund.

A second direction test proves a token-to-ETH exact-input swap can create a ticket from executed native output. Unit tests cover the 1.96x payout, 20% volume cap, 80% utilisation limit and pro-rata redemption formula.

Adversarial tests reject a wrong PoolManager, wrong router, alternate PoolKey, malformed hook data, replayed or stale pending wagers and exact-output wager mode. They also cover stake bounds, bankroll capacity, atomic deadline and slippage failures, both randomness timeout paths, repeated fee claims, repeated ticket claims and repeated settlement.

The stateful suite checks that WETH covers all game liabilities, reserved exposure stays within both caps, bankroll shares remain conserved, terminal states do not return to Active and no ticket pays twice.

## Implemented launch evidence

Source:

- `src/bankroll/BankrollLaunchV1.sol`
- `src/bankroll/PermanentPositionLocker.sol`
- `src/bankroll/BankrollHookFactory.sol`

Test:

- `test/bankroll/BankrollLaunchV1.t.sol`

The launch integration test uses real Uniswap v4 PoolManager, PositionManager and Permit2 test deployments. It uses a local deterministic UERC20 factory because no Ethereum factory runtime has been selected or verified.

The test proves the predicted token, mined hook and bound router configuration. It also proves fixed supply, canonical PoolId, launch hash, permanent position-NFT ownership, empty launcher and PositionManager token custody, an initial buy and mandatory fee accrual. It does not prove a production dependency deployment or every failed-launch case.

## Dependency records

The npm lock pins OpenZeppelin Contracts 5.5.0, OpenZeppelin Uniswap Hooks 1.1.1, Uniswap v4 Core 1.0.2, Uniswap v4 Periphery 1.0.3 and Chainlink Contracts 1.5.0. Dependencies retain their own licences as recorded in `NOTICE.md` and package metadata.

Chainlink's current Ethereum direct-funding documentation lists wrapper `0x02aae1A04f9828517b3007f83f6181900CaD910c` and coordinator `0xD7f86b4b8Cae7D942340FF628F82735b7a20893a`. These addresses have not been runtime-verified or used in a fork test here.

## Remaining evidence work

- bind the wager router to an exact deployment record with runtime evidence
- select and verify the Ethereum PoolManager, PositionManager, UERC20 factory, WETH and VRF wrapper records
- extend the invariant handler to Programmable fee claims and native claim backing
- run Slither and pinned mainnet-fork tests
- add the remaining failed-launch and hostile dependency tests
- keep the application package bound to the reviewed public source commit
- obtain maintainer and independent review

No evidence here proves an audit, acceptance, deployment, source verification, routing approval or product availability.
