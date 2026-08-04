# Security

This code is a prototype. It has not had an independent audit. Do not deploy it with real value.

## Trust boundaries

The hook trusts the immutable Uniswap v4 PoolManager to authenticate callbacks and settle deltas. It accepts one exact PoolKey and rejects other pools.

The hook trusts the immutable wager router only to identify a player and bind staged WETH to one exact-input swap. The router cannot change odds, limits, deadlines or the randomness source.

The hook trusts the immutable randomness adapter to return the Chainlink VRF word for one request. The adapter accepts fulfilment only through the configured wrapper base contract and allows only its immutable consumer to consume a word.

The CREATE2 factory has no admin role. A caller supplies hook init code because embedding it would make the factory exceed EIP-170 at the compiler setting required by Uniswap. The factory checks the mined permission bits and the deployed hook's factory, PoolManager, token and WETH bindings before it deploys and binds the router.

The launcher trusts its immutable PoolManager, PositionManager, UERC20 factory, WETH and randomness adapter. It validates the deployed hook's complete launch configuration before pool initialization. The permanent locker accepts position NFTs only from its immutable PositionManager. It exposes fee collection but no position transfer, liquidity decrease, arbitrary call, rescue or admin function.

## Protected value

The hook accounts for:

- bankroll WETH
- staged and open WETH stakes
- player WETH claims
- native PoolManager claims backing the Programmable fee
- non-transferable bankroll shares and tickets
- the permanent v4 position NFT and any deliberate launch-token dust held by its locker

Direct WETH donations do not mint shares or increase recorded bankroll assets. There is no rescue or sweep function. This avoids an administrator but means accidental token transfers can remain inaccessible.

## Main failure cases

- A wrong PoolManager caller or PoolKey reverts.
- Non-empty hook data from any address except the immutable router reverts.
- Exact-output wager attempts revert. Ordinary exact-output swaps remain supported.
- Unsupported game partial fills revert the complete router transaction.
- A failed VRF request does not change the game state because the request is atomic.
- A fulfilled request prevents timeout. Permissionless consumption is the recovery path.
- Settlement work is bounded to 16 tickets per batch and 64 tickets per season.
- Failed WETH or native transfers revert before liabilities remain reduced.
- The immutable Programmable owner is the only fee claimant. The project has no fee share or redirect authority.

## Known gaps

- There is no mainnet or fork deployment evidence.
- Slither is not installed in the local environment.
- Stateful invariant coverage and independent review are still required.
- Failed-launch, malicious token-factory and position-fee collection cases need more adversarial tests.
- The Chainlink wrapper addresses and request parameters need deployment-time confirmation against the target network.
- The exact UERC20 factory, PoolManager, PositionManager and WETH deployment records need confirmation against the target network.
- Product UI, quoting, indexing, monitoring and routing support are not implemented or approved.

Report security issues privately before public disclosure. Do not include keys, RPC credentials or live exploit details in an issue.
