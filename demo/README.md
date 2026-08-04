# Bankroll Hook demo

This React MVP lets a user set an ETH swap amount, choose a WETH wager and review the fixed-odds ticket. Wallet connection is optional in demo mode and required for a configured transaction.

It runs in demo mode until you provide a deployed `BankrollRouter` address. Demo mode does not send a transaction or claim that the contracts are deployed.

## Run the demo

You need Bun 1.3 or later.

```sh
bun install
bun run dev
```

Open the local URL printed by Vite.

Run the checks with:

```sh
bun run lint
bun run build
```

## Enable wallet transactions

Copy `.env.example` to `.env.local` and set:

```text
VITE_BANKROLL_ROUTER_ADDRESS=0x...
VITE_MINIMUM_TOKEN_OUT_WEI=1
VITE_TARGET_CHAIN_ID=11155111
```

You can also set `VITE_WALLETCONNECT_PROJECT_ID` to add WalletConnect. Without it, the demo uses an injected browser wallet.

The current transaction path calls `gameSwapExactInput` for an ETH-to-token wager. The app will not enable transactions without a non-zero minimum token output and an explicit Ethereum or Sepolia chain id. Use a current quote for the minimum output before each transaction. The environment value is only a temporary MVP input.

## State and effects

Zustand holds the shared wager inputs. Wagmi and TanStack Query hold wallet and transaction state.

The demo source does not use `useEffect` or `useLayoutEffect`. The retained Fluid Functionalism button uses event-driven hover and pressed states. The stake control uses a native range input.
