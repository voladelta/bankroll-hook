import { isAddress, parseAbi, type Address } from "viem"

export const bankrollRouterAbi = parseAbi([
  "function gameSwapExactInput(bool zeroForOne, uint256 amountIn, uint256 minimumAmountOut, uint128 stake, uint160 sqrtPriceLimitX96, uint256 deadline, address recipient) payable returns (uint256 amountOut, uint64 userNonce)",
])

const configuredRouter = import.meta.env.VITE_BANKROLL_ROUTER_ADDRESS ?? ""
const configuredMinimumOutput = import.meta.env.VITE_MINIMUM_TOKEN_OUT_WEI ?? ""
const configuredChainId = Number(import.meta.env.VITE_TARGET_CHAIN_ID)

export const bankrollRouterAddress = isAddress(configuredRouter)
  ? (configuredRouter as Address)
  : undefined

export const minimumTokenOutput = /^\d+$/.test(configuredMinimumOutput)
  ? BigInt(configuredMinimumOutput)
  : undefined

export const targetChainId = configuredChainId === 1 || configuredChainId === 11_155_111
  ? configuredChainId
  : undefined

export const transactionsConfigured = Boolean(
  bankrollRouterAddress && minimumTokenOutput && minimumTokenOutput > 0n && targetChainId,
)

export const minimumSqrtPriceLimit = 4_295_128_740n
