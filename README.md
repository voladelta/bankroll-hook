# Bankroll Hook

Bankroll Hook adds an optional fixed-odds wager to one canonical Uniswap v4 launch pool. Ordinary swaps continue to use standard v4 routers. A wager must use the immutable narrow router and can only attach to a successful exact-input swap.

This repository is a local prototype. It is not audited, deployed, accepted by Programmable, supported by Uniswap routing or available to users.

## What is implemented

- One native ETH and launched-token PoolKey with zero LP fee and tick spacing 200.
- A fixed-supply token launcher with deterministic token, hook, router and position-locker addresses.
- One-sided liquidity held by a permanent locker with no transfer, decrease, rescue or admin path.
- An optional creator buy in the same launch transaction, charged as an ordinary swap and protected by a creator-selected minimum token output.
- The six hook permissions represented by address mask `0x30cc`.
- A cumulative 10 bps Programmable fee on executed gross native quote volume in all four swap quadrants, with numerator dust carried by PoolId, currency and immutable owner.
- An immutable owner-only fee claim to an address chosen for that claim.
- A fixed Funding, Active, Closed, RandomnessRequested, Seeded or Expired, and Finalized lifecycle.
- Permissionless WETH bankroll deposits during Funding and pro-rata redemption after the game.
- Up to 64 non-transferable tickets with a 1.96x gross payout.
- A 20% stake-to-executed-volume cap and an 80% bankroll-utilisation cap.
- Chainlink VRF v2.5 direct-funding adapter code. The callback only stores the random word.
- Permissionless randomness consumption, ticket settlement, timeout and finalisation.

The launch flow is implemented and tested locally against Uniswap v4 PoolManager and PositionManager. It uses a narrow interface to an external UERC20 factory. The exact Ethereum factory, manager, WETH and VRF deployment records remain unverified. See [EVIDENCE.md](submissions/bankroll-hook/EVIDENCE.md).

## Build and test

Requirements:

- Foundry with Solidity 0.8.26 support
- Node.js and npm
- Bun 1.3 or later for the React demo

Run:

```sh
npm install --ignore-scripts
npm run build
forge test -vv
forge lint
```

The project pins Solidity 0.8.26, Cancun and 5,000 optimiser runs. The larger optimiser setting avoids a Solidity Yul stack-depth failure in the pinned Uniswap Pool library. The build checks each first-party deployable against the EIP-170 runtime and EIP-3860 init-code limits.

## React demo

The [demo](demo/README.md) is a Bun and Vite React MVP. It uses wagmi for wallet and transaction state, Zustand for wager inputs and a Fluid Functionalism button.

Run it with:

```sh
cd demo
bun install
bun run dev
```

The app starts in demo mode. Add a deployed router address, quoted minimum output and target chain to `demo/.env.local` to enable the ETH-to-token transaction path.

## Contract map

- `BankrollHook.sol` enforces the pool, fee, bankroll, ticket and settlement rules.
- `BankrollRouter.sol` supports wagered exact-input swaps in both directions.
- `BankrollHookFactory.sol` deploys mined hook init code, validates immutable bindings and binds one router.
- `BankrollLaunchV1.sol` creates the fixed token, hook, router, pool, locked position and optional initial buy.
- `PermanentPositionLocker.sol` holds the position NFT permanently and lets anyone collect fees for the creator.
- `ChainlinkVrfV25Adapter.sol` isolates direct-funded VRF request and fulfilment state.

The design and value-flow details are in [MECHANISM.md](MECHANISM.md). The security assumptions are in [SECURITY.md](SECURITY.md).
