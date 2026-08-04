import {
  Activity,
  ArrowUpRight,
  Check,
  ChevronRight,
  CircleDotDashed,
  Clock3,
  ExternalLink,
  RotateCcw,
  ShieldCheck,
  Ticket,
  Wallet,
} from "lucide-react"
import { useState, type CSSProperties } from "react"
import { parseEther } from "viem"
import {
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi"

import { Button } from "../components/ui/button"
import {
  bankrollRouterAbi,
  bankrollRouterAddress,
  minimumSqrtPriceLimit,
  minimumTokenOutput,
  targetChainId,
  transactionsConfigured,
} from "./contracts"
import { maximumStake, minimumStake, useWagerStore } from "./store"

const season = {
  bankroll: 42.8,
  availableExposure: 18.24,
  tickets: 17,
  capacity: 64,
  blocksRemaining: 392,
}

function compactAddress(address: string) {
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

function displayEth(value: number, digits = 3) {
  return value.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: digits,
  })
}

function App() {
  const connection = useConnection()
  const connectors = useConnectors()
  const connect = useConnect()
  const disconnect = useDisconnect()
  const [walletMenuOpen, setWalletMenuOpen] = useState(false)

  const connectWallet = (connector = connectors[0]) => {
    if (!connector) return
    connect.mutate({ connector })
    setWalletMenuOpen(false)
  }

  return (
    <div className="app-shell">
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Bankroll Hook home">
          <span className="brand-mark" aria-hidden="true">
            <CircleDotDashed size={18} />
          </span>
          <span>BANKROLL</span>
          <span className="brand-slash">/</span>
          <span>HOOK</span>
        </a>

        <div className="header-actions">
          <span className="network-label">
            <span className="network-dot" />
            {transactionsConfigured ? connection.chain?.name ?? "Ethereum" : "Demo mode"}
          </span>
          <div
            className="wallet-control"
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget)) setWalletMenuOpen(false)
            }}
            onKeyDown={(event) => {
              if (event.key === "Escape") setWalletMenuOpen(false)
            }}
          >
            <Button
              variant={connection.isConnected ? "secondary" : "primary"}
              size="lg"
              leadingIcon={Wallet}
              active={walletMenuOpen}
              aria-expanded={walletMenuOpen}
              aria-controls="wallet-menu"
              onClick={() =>
                connection.isConnected
                  ? setWalletMenuOpen((open) => !open)
                  : connectors.length > 1
                    ? setWalletMenuOpen((open) => !open)
                    : connectWallet()
              }
              loading={connect.isPending}
            >
              {connection.address ? compactAddress(connection.address) : "Connect wallet"}
            </Button>
            <div
              id="wallet-menu"
              className="wallet-menu"
              role="menu"
              aria-label="Wallet options"
              aria-hidden={!walletMenuOpen}
              data-open={walletMenuOpen}
              inert={!walletMenuOpen}
            >
                {connection.isConnected ? (
                  <button
                    type="button"
                    role="menuitem"
                    onClick={() => {
                      disconnect.mutate()
                      setWalletMenuOpen(false)
                    }}
                  >
                    Disconnect
                    <ChevronRight size={15} />
                  </button>
                ) : (
                  connectors.map((connector) => (
                    <button key={connector.uid} type="button" role="menuitem" onClick={() => connectWallet(connector)}>
                      {connector.name}
                      <ChevronRight size={15} />
                    </button>
                  ))
                )}
              </div>
          </div>
        </div>
      </header>

      <main id="top">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-copy">
            <div className="eyebrow">
              <span>Season 01</span>
              <span className="status-live">Active</span>
            </div>
            <h1 id="hero-title">One swap.<br />One wager.</h1>
            <p>
              Buy the launch token and attach a fixed-odds WETH wager to the same successful Uniswap v4 swap.
            </p>
          </div>

          <SeasonStatus />
        </section>

        <section className="workspace" aria-label="Wager workspace">
          <WagerComposer
            connected={connection.isConnected}
            address={connection.address}
            chainId={connection.chainId}
            connecting={connect.isPending}
            onConnect={() => connectWallet()}
          />
          <TicketPreview />
        </section>

        <section className="mechanism" aria-labelledby="mechanism-title">
          <div>
            <span className="section-index">03 / Rules</span>
            <h2 id="mechanism-title">The hook refuses bad bets before they exist.</h2>
          </div>
          <div className="rule-list">
            <Rule icon={ShieldCheck} title="Reserved first" text="Maximum loss is reserved from the WETH bankroll before a ticket is created." />
            <Rule icon={Activity} title="Executed volume" text="Stake is capped at 20% of the native quote volume that the swap actually executes." />
            <Rule icon={Clock3} title="Finite exit" text="If randomness stalls, the immutable timeout turns every open stake into a refund." />
          </div>
        </section>
      </main>

      <footer>
        <span>Bankroll Hook MVP</span>
        <a href="https://github.com/0xprogrammable/programmable" target="_blank" rel="noreferrer">
          0xProgrammable <ExternalLink size={13} />
        </a>
        <span>Prototype · not audited</span>
      </footer>
    </div>
  )
}

function SeasonStatus() {
  return (
    <aside className="season-status" aria-label="Current season status">
      <div className="season-heading">
        <span>{transactionsConfigured ? "Live bankroll" : "Simulated bankroll"}</span>
        <span>{season.blocksRemaining} blocks left</span>
      </div>
      <strong>{season.bankroll.toFixed(2)} <small>WETH</small></strong>
      <div className="exposure-track" aria-label={`${season.availableExposure} WETH available exposure`}>
        <span style={{ width: `${(season.availableExposure / season.bankroll) * 100}%` }} />
      </div>
      <div className="season-meta">
        <span><b>{season.availableExposure.toFixed(2)}</b> available exposure</span>
        <span><b>{season.tickets}/{season.capacity}</b> tickets</span>
      </div>
    </aside>
  )
}

type WagerComposerProps = {
  connected: boolean
  address?: `0x${string}`
  chainId?: number
  connecting: boolean
  onConnect: () => void
}

function WagerComposer({ connected, address, chainId, connecting, onConnect }: WagerComposerProps) {
  const { amount, stake, setAmount, setStake, submitDemo } = useWagerStore()
  const write = useWriteContract()
  const switchChain = useSwitchChain()
  const receipt = useWaitForTransactionReceipt({ hash: write.data })

  const amountValue = Number(amount)
  const stakeLimit = maximumStake(amount)
  const validAmount = Number.isFinite(amountValue) && amountValue > 0
  const validStake = stake >= minimumStake && stake <= stakeLimit
  const canSubmit = validAmount && validStake
  const deployed = transactionsConfigured
  const wrongChain = deployed && chainId !== targetChainId
  const busy = write.isPending || receipt.isLoading

  const submit = () => {
    if (!deployed) {
      if (canSubmit) submitDemo()
      return
    }
    if (!connected) {
      onConnect()
      return
    }
    if (wrongChain && targetChainId) {
      switchChain.mutate({ chainId: targetChainId })
      return
    }
    if (!canSubmit || !address) return
    if (!transactionsConfigured || !bankrollRouterAddress || !minimumTokenOutput || !targetChainId) return

    const amountIn = parseEther(amount)
    const wager = parseEther(stake.toFixed(18))
    write.mutate({
      address: bankrollRouterAddress,
      abi: bankrollRouterAbi,
      functionName: "gameSwapExactInput",
      args: [
        true,
        amountIn,
        minimumTokenOutput,
        wager,
        minimumSqrtPriceLimit,
        BigInt(Math.floor(Date.now() / 1_000) + 20 * 60),
        address,
      ],
      value: amountIn + wager,
      chainId: targetChainId,
    })
  }

  const buttonLabel = !deployed
    ? "Preview wager"
    : !connected
      ? "Connect wallet to continue"
    : wrongChain
      ? `Switch to ${targetChainId === 1 ? "Ethereum" : "Sepolia"}`
    : deployed
      ? "Swap and place wager"
      : "Preview wager"

  return (
    <div className="composer">
      <div className="panel-heading">
        <div>
          <span className="section-index">01 / Compose</span>
          <h2>Buy BANK + wager</h2>
        </div>
        <span className="mode-tag">Exact input</span>
      </div>

      <label className="amount-field">
        <span>You swap</span>
        <div>
          <input
            type="number"
            min="0"
            step="0.01"
            inputMode="decimal"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            aria-describedby="amount-help"
          />
          <span>ETH</span>
        </div>
        <small id="amount-help">The 10 bps Programmable fee applies to executed native volume.</small>
      </label>

      <div className="stake-field">
        <div className="stake-label">
          <div>
            <span>Wager stake</span>
            <small>Maximum 20% of swap volume</small>
          </div>
          <strong>{displayEth(stake)} WETH</strong>
        </div>
        <input
          type="range"
          aria-label="Wager stake"
          value={stake}
          min={minimumStake}
          max={stakeLimit}
          step={0.01}
          onChange={(event) => setStake(event.currentTarget.valueAsNumber)}
          disabled={!validAmount || stakeLimit === minimumStake}
          className="wager-slider"
          style={{
            "--stake-progress": `${stakeLimit > minimumStake ? ((stake - minimumStake) / (stakeLimit - minimumStake)) * 100 : 0}%`,
          } as CSSProperties}
        />
        <div className="stake-scale" aria-hidden="true">
          <span>{minimumStake} WETH</span>
          <span>{displayEth(stakeLimit)} WETH max</span>
        </div>
      </div>

      <div className="composer-summary">
        <span>Wallet sends</span>
        <strong>{validAmount ? displayEth(amountValue + stake) : "—"} ETH</strong>
      </div>

      <Button
        size="lg"
        className="submit-button"
        trailingIcon={ArrowUpRight}
        loading={connecting || busy || switchChain.isPending}
        disabled={!canSubmit && (!deployed || connected)}
        onClick={submit}
      >
        {buttonLabel}
      </Button>

      {!deployed && (
        <p className="demo-note">Demo mode. Add the router, minimum output and target chain to <code>.env.local</code> to enable transactions.</p>
      )}
      {write.error && <p className="form-message error">Transaction failed: {write.error.message.split("\n")[0]}</p>}
      {receipt.isSuccess && <p className="form-message success"><Check size={15} /> Wager included onchain.</p>}
    </div>
  )
}

function TicketPreview() {
  const { amount, stake, demoSubmitted, resetDemo } = useWagerStore()
  const amountValue = Number(amount)
  const payout = stake * 1.96
  const profit = payout - stake
  const fee = Number.isFinite(amountValue) ? amountValue * 0.001 : 0

  return (
    <aside className="ticket-preview" aria-label="Ticket preview">
      <div className="panel-heading">
        <div>
          <span className="section-index">02 / Ticket</span>
          <h2 aria-live="polite">{demoSubmitted ? "Ready to sign" : "If you win"}</h2>
        </div>
        <Ticket size={22} strokeWidth={1.5} />
      </div>

      <div className="odds-mark" aria-label="50 percent chance to win">
        <span>50</span>
        <i>/</i>
        <span>50</span>
      </div>
      <p className="odds-copy">One verified random seed decides the season. Every ticket has equal win and loss probability.</p>

      <dl className="ticket-math">
        <div><dt>Stake</dt><dd>{displayEth(stake)} WETH</dd></div>
        <div><dt>Gross payout</dt><dd>{displayEth(payout)} WETH</dd></div>
        <div><dt>Profit on win</dt><dd>+{displayEth(profit)} WETH</dd></div>
        <div><dt>Volume fee</dt><dd>{displayEth(fee, 5)} ETH</dd></div>
      </dl>

      <div className="house-edge">
        <span>Expected house edge</span>
        <strong>2%</strong>
      </div>

      {demoSubmitted && (
        <button className="reset-preview" type="button" onClick={resetDemo}>
          <RotateCcw size={14} /> Edit preview
        </button>
      )}
    </aside>
  )
}

function Rule({ icon: Icon, title, text }: { icon: typeof ShieldCheck; title: string; text: string }) {
  return (
    <article>
      <Icon size={20} strokeWidth={1.5} />
      <div>
        <h3>{title}</h3>
        <p>{text}</p>
      </div>
    </article>
  )
}

export default App
