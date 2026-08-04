/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_WALLETCONNECT_PROJECT_ID?: string
  readonly VITE_BANKROLL_ROUTER_ADDRESS?: string
  readonly VITE_MINIMUM_TOKEN_OUT_WEI?: string
  readonly VITE_TARGET_CHAIN_ID?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
