import { create } from "zustand"

type WagerState = {
  amount: string
  stake: number
  demoSubmitted: boolean
  setAmount: (amount: string) => void
  setStake: (stake: number) => void
  submitDemo: () => void
  resetDemo: () => void
}

const minimumStake = 0.01

function maximumStake(amount: string) {
  const parsed = Number(amount)
  return Number.isFinite(parsed) && parsed > 0
    ? Math.max(minimumStake, parsed * 0.2)
    : minimumStake
}

export const useWagerStore = create<WagerState>((set) => ({
  amount: "0.50",
  stake: 0.05,
  demoSubmitted: false,
  setAmount: (amount) =>
    set((state) => ({
      amount,
      stake: Math.min(state.stake, maximumStake(amount)),
      demoSubmitted: false,
    })),
  setStake: (stake) => set({ stake, demoSubmitted: false }),
  submitDemo: () => set({ demoSubmitted: true }),
  resetDemo: () => set({ demoSubmitted: false }),
}))

export { maximumStake, minimumStake }
