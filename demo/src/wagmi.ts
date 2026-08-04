import { createConfig, http } from "wagmi"
import { injected, walletConnect } from "wagmi/connectors"
import { mainnet, sepolia } from "wagmi/chains"

const walletConnectProjectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID

export const wagmiConfig = createConfig({
  chains: [mainnet, sepolia],
  connectors: walletConnectProjectId
    ? [injected(), walletConnect({ projectId: walletConnectProjectId, showQrModal: true })]
    : [injected()],
  transports: {
    [mainnet.id]: http(),
    [sepolia.id]: http(),
  },
})

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig
  }
}
