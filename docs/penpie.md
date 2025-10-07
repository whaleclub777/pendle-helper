## Penpie — architecture & MasterPenpie pipeline

This document summarizes how the Penpie system works with an emphasis on the `MasterPenpie` pipeline: pools, receipt tokens, reward accounting and interactions with rewarders and special locker pools (vlPenpie, mPendleSV).

### Overview

- `Penpie` (PNP) is the protocol reward token (an OFT for cross-chain via LayerZero).
- `MasterPenpie` is the central reward manager that mints/distributes PNP rewards over time to stakers across pools.
- Each pool is a stakeable token + a receipt token (usually `PenpieReceiptToken`) used to represent user positions.
- `BaseRewardPoolV2` (rewarder) handles additional bonus tokens per pool (queued rewards, per-token accounting).
- `PenpieReader` is a read-only helper used by frontends to fetch pool snapshots, prices and bribe/epoch info.

### Key contracts and files

- `rewards/MasterPenpie.sol` — master controller for pools, emission math, per-user accounting.
- `rewards/PenpieReceiptToken.sol` — receipt token that calls MasterPenpie hooks on transfer to keep reward accounting consistent.
- `rewards/BaseRewardPoolV2.sol` — rewarder handling bonus tokens and queuing/distribution.
- `VLPenpie.sol` — locked PNP contract; interacts with MasterPenpie via dedicated entry points.
- `pendle/PendleRushV6.sol` — conversion/incentive flows for PENDLE → mPENDLE, uses MasterPenpie for staking and fetching rewards.
- `BuyBackBurnProvider.sol` and `DutchAuction.sol` — auxiliary components for buybacks and auctions.

### High-level pipeline (deposit → accounting → claim)

1. Add pool / create receipt token
   - Owner or pool manager creates a pool with an allocation point, a `stakingToken` and a `receiptToken`. `ERC20FactoryLib` helps create `PenpieReceiptToken` and a `BaseRewardPoolV2` rewarder.

2. Deposit (user stakes tokens)
   - User calls `MasterPenpie.deposit(stakingToken, amount)` (or a helper calls `depositFor`).
   - MasterPenpie mints `receiptToken` to the user and transfers staking tokens into the contract.
   - Receipt token `mint` triggers transfer hooks which call `MasterPenpie.beforeReceiptTokenTransfer` and `afterReceiptTokenTransfer` to update pools and harvest rewards before balances change.

3. Receipt token transfer
   - Any transfer of the receipt token calls `beforeReceiptTokenTransfer` (update & harvest for from/to) and `afterReceiptTokenTransfer` (update `user.amount`, `user.rewardDebt`, `pool.totalStaked`). This preserves the invariant for pending rewards.

4. Withdraw
   - `MasterPenpie.withdraw` burns receipt tokens and transfers underlying staking tokens back to the user.
   - `before`/`after` hooks ensure pending rewards are captured and accounting updated.

5. Reward accrual (per-pool)
   - On `updatePool`, if pool has stake and `totalAllocPoint > 0`:
     - compute `multiplier = block.timestamp - pool.lastRewardTimestamp`
     - `penpieReward = multiplier * penpiePerSec * pool.allocPoint / totalAllocPoint`
     - `pool.accPenpiePerShare += (penpieReward * 1e12) / pool.totalStaked`
   - User pending PNP: `(user.amount * accPenpiePerShare) / 1e12 - user.rewardDebt`.

6. Harvesting & claiming
   - `_harvestPenpie` moves computed pending into `user.unClaimedPenpie` (doesn't immediately transfer PNP).
   - `multiclaim` / `multiclaimFor` / `multiclaimOnBehalf` call `_multiClaim`, which:
     - updates pools, sums claimable amounts across requested pools, calls bonus rewarders, and sends PNP.
     - For `vlPenpie` pool, PNP distribution is queued to a special vl rewarder via `queuePenpie` rather than direct transfer.
   - Bonus tokens (rewarder) are fetched via rewarder `getReward` / `getRewards`.

### Rewarder integration

- `BaseRewardPoolV2` is a common rewarder implementation. It tracks `rewardPerTokenStored` and `queuedRewards` per bonus token.
- `queueNewRewards` and `donateRewards` provision reward tokens into the rewarder. If `totalStake == 0`, rewards are queued.
- MasterPenpie calls `rewarder.updateFor`/`getRewards`/`getReward` to synchronize or claim bonus tokens for users.
- `ARBRewarder` may be configured to coordinate ARB distribution before rewarder updates.

### Special pools: `vlPenpie` and `mPendleSV`

- `vlPenpie` is a locker pool whose deposit/withdraw functions on MasterPenpie are callable only by the `vlPenpie` contract. Rewards to `vlPenpie` are handled via a special rewarder and `queuePenpie`.
- `mPendleSV` works similarly; MasterPenpie exposes `depositMPendleSVFor` / `withdrawMPendleSVFor` for the locker contract to call.

### Important functions (cheat-sheet)

- `poolLength()` — number of registered pools
- `getPoolInfo(stakingToken)` — emission, allocPoints, pool size and global total point
- `stakingInfo(stakingToken, user)` — user's staked and available amounts
- `pendingTokens(stakingToken, user, token)` — pending PNP and a specific bonus token amount
- `deposit(stakingToken, amount)` / `depositFor(stakingToken, for, amount)` — stake
- `withdraw(stakingToken, amount)` — withdraw
- `multiclaim(stakingTokens[])` / `multiclaimFor(...)` — claim PNP & bonus tokens across many pools
- Admin: `createPool`, `add`, `set`, `removePool`, `updateEmissionRate`

### Admin & security notes

- `PoolManagers` manage pool creation and updates. `AllocationManagers` / whitelisted managers can bulk update allocations.
- `receiptToStakeToken` mapping prevents reusing a receipt token across pools.
- `updatePool`/`massUpdatePools` gas cost: `massUpdatePools` can be expensive; code uses `updatePool` selectively.
- `removePool` is powerful (used during incidents) — it deletes pool mappings and reduces `totalAllocPoint`.

### Edge cases and integration gotchas

- If `totalAllocPoint == 0`, emission accrual is effectively paused until a pool is assigned allocation points.
- Rewarders rely on being funded; if a rewarder lacks tokens at claim time, payouts fail or are smaller — frontends should show queued/available reward balances.
- Receipt-token transfers must go through the token contract to trigger MasterPenpie hooks; direct balance manipulation breaks invariants.

### Next steps / suggestions

- Add a sequence diagram (deposit → mint → hooks → updatePool → claim) in `docs/` for quick onboarding.
- Produce small `ethers.js` snippets for common flows (stake, check pending, multiclaim) and save in `docs/examples.md` if useful.
- Extract the minimal ABI for `MasterPenpie` used by frontends and save as `docs/masterpenpie.abi.json`.

If you'd like, I can add a diagram and the example `ethers.js` snippets next — which would be most useful for you?
