# Mechanism

## Product rule

A trader may attach one WETH wager to a successful exact-input swap in either direction. The ticket wins or loses with equal probability. A winning ticket pays 1.96 times its stake. The expected house edge is 2% of stake.

Ordinary swaps do not create tickets. They can use standard v4 routers with empty hook data in all four direction and exactness combinations.

## Pool and fee

The canonical pool uses native ETH as currency0, the launched token as currency1, an LP fee of zero and tick spacing 200.

The launcher creates a fixed one-billion-token supply through an external UERC20 factory. It deploys the mined hook and its narrow router, initializes the pool and puts the supply into a one-sided position. A dedicated locker owns the position NFT permanently. It cannot transfer or reduce the position, rescue assets or change its fee recipient.

The creator may include an initial ETH buy in the launch transaction and supplies the minimum acceptable token output. It uses empty hook data, so it pays the Programmable fee but does not create a wager. A failure in token creation, hook deployment, pool initialization, liquidity formation, the minimum-output check or the initial buy reverts the complete launch.

The hook charges the mandatory 10 bps Programmable fee on executed gross native quote volume. It has no project fee. It charges specified-quote swaps in `beforeSwap` and unspecified-quote swaps in `afterSwap`:

| Swap | Collection callback |
| --- | --- |
| ETH to token, exact input | `beforeSwap` |
| ETH to token, exact output | `afterSwap` |
| Token to ETH, exact input | `afterSwap` |
| Token to ETH, exact output | `beforeSwap` |

Each fee calculation adds the prior numerator remainder before division. The hook carries the new remainder by canonical PoolId, native currency and immutable Programmable owner, so splitting successful micro-swaps cannot avoid the lifetime 10 bps entitlement. Claims do not clear that remainder.

The hook stores the whole-unit fee as native PoolManager ERC-6909 claims. The liability uses the same PoolId, currency and owner scope. Only that owner can claim. It may choose the destination for each claim.

## Funding and exposure

Bankroll providers deposit WETH during the fixed Funding window. Deposits mint internal shares 1:1. Providers may withdraw 1:1 until the Funding deadline.

Anyone can activate the game after the deadline if the bankroll meets the immutable minimum. Otherwise, anyone can cancel it. No administrator can change the result.

Each ticket reserves its maximum possible loss before the swap. For stake `s`:

```text
gross payout = floor(1.96 × s)
reserved exposure = gross payout − s
```

The hook rejects a ticket when:

- the stake is outside the immutable minimum and maximum
- the stake exceeds 20% of executed gross native quote volume
- total reserved exposure would exceed 80% of current bankroll assets
- total reserved exposure would exceed current bankroll assets
- the season already has 64 tickets

## Wager routing

The narrow router stages the WETH stake before opening a PoolManager unlock. It encodes a versioned pending identifier in hook data. The hook accepts non-empty hook data only from that immutable router, in the same block, for an exact-input swap during Active.

The hook creates the ticket only in `afterSwap`. It therefore uses actual executed native quote volume. A reverted or partially filled unsupported game swap reverts the staged stake and all associated state.

## Randomness and settlement

The season closes at its block deadline or when it reaches 64 tickets. Anyone can request direct-funded Chainlink VRF v2.5 randomness by paying the exact quoted fee within their chosen maximum.

The VRF callback stores one word only. It does not loop, settle tickets or transfer value. Anyone can later pull the word into the hook and settle tickets in bounded batches.

Each ticket derives its outcome from the season seed, canonical PoolId and ticket id. A win moves the reserved exposure from the bankroll to player liability. A loss moves the stake into the bankroll. The accounting equation is:

```text
WETH balance ≥ bankroll assets + open stake liability + player claim liability
```

If nobody requests randomness in time, or an unfulfilled request times out, anyone can expire randomness. Open stakes then become refundable player liabilities. Bankroll providers can redeem only after finalisation or an unfunded cancellation.
