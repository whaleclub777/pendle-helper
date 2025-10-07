## vePENDLE boost & reward claim (quick reference)

This page summarises how ve-based boosting and reward claiming work for Pendle markets (v3). It references the on-chain implementations in the repo (notably `PendleGauge`, `PendleMarketV3` and `RewardManager`).

### Where to look in the code
- Boost calculation: `lib/pendle-core-v2-public/contracts/core/Market/PendleGauge.sol` (`_calcVeBoostedLpBalance`)
- Market entrypoint: `lib/pendle-core-v2-public/contracts/core/Market/v3/PendleMarketV3.sol` (`redeemRewards`)
- Reward accounting & distribution: `lib/pendle-core-v2-public/contracts/core/RewardManager/RewardManager*.sol`
- SY rewards interface: `lib/pendle-core-v2-public/contracts/interfaces/IStandardizedYield.sol` (`claimRewards`)
- Gauge controller: `lib/pendle-core-v2-public/contracts/LiquidityMining/GaugeController/PendleGaugeControllerBaseUpg.sol` (`redeemMarketReward`)

### Boost formula (exact)
The gauge computes a "ve-boosted" LP balance using these steps (see `PendleGauge._calcVeBoostedLpBalance`):

- Constant: `TOKENLESS_PRODUCTION = 40` (percent). This is the baseline production everyone gets.
- Compute base: `base = lpBalance * 40 / 100` (40% of the user's LP balance).
- If total ve supply > 0, compute extra:

  extra = (((totalStaked * userVeBalance) / totalVeSupply) * (100 - 40)) / 100

  where `totalStaked` is the market's total LP (gauge `_totalStaked()`), `userVeBalance` and `totalVeSupply` come from `vePENDLE.totalSupplyAndBalanceCurrent(user)`.

- ve-boosted balance = `base + extra`
- active balance used for rewards = `min(ve-boosted balance, lpBalance)` (cannot exceed the user's LP balance)

In short: everyone gets 40% of their LP as base production; the remaining 60% is distributed proportionally to ve-holders based on their share of total ve supply, and the final active balance is capped at the user's LP balance.

Notes:
- The code calls `vePENDLE.totalSupplyAndBalanceCurrent(user)` (a non-view helper) to obtain an up-to-date ve balance when computing the boost.
- Arithmetic uses the project's fixed-point helpers (rounding-down semantics) so tiny rounding differences can happen.

### How rewards are claimed (call flow)
Call the market's public function:

- `PendleMarketV3.redeemRewards(address user)`

What happens inside (high level):

1. `_redeemRewards(user)` is invoked (from `PendleGauge` / `RewardManager`).
2. `_updateAndDistributeRewards(user)` runs:
   - `_updateRewardIndex()` refreshes per-token reward indexes for the current block.
   - `_updateRewardIndex()` first calls `_redeemExternalReward()` which:
       - Calls `IStandardizedYield(SY).claimRewards(address(this))` — claims SY reward tokens owed to the market.
       - Calls `IPGaugeController(gaugeController).redeemMarketReward()` — pulls PENDLE allocated for the market from the gauge controller.
   - With newly received tokens, indexes are advanced and the user's `userReward[token][user].accrued` is updated using the user's reward shares (the `activeBalance` computed using the boost formula).
3. `_doTransferOutRewards(user, user)` transfers the accrued reward token amounts from the market contract to the `user` and clears their accrued counters.

The returned array from `redeemRewards` contains reward amounts in the same order as `getRewardTokens()`.

### Which tokens are returned
- `market.getRewardTokens()` returns the SY protocol reward tokens (from `SY.getRewardTokens()`) and ensures `PENDLE` is included (if not already present). The `redeemRewards` call returns amounts in the order of that array.

### Useful read-only helpers
- `market.getRewardTokens()` — list of reward token addresses.
- `market.activeBalance(user)` — stored active balance (may be stale until updates happen).
- `market.totalActiveSupply()` — denominator used to compute per-share reward amounts.
- `vePENDLE.balanceOf(user)` (view) or `vePENDLE.totalSupplyAndBalanceCurrent(user)` (non-view current helper used on-chain) — user's ve balance and total ve supply.
- `market.userReward(token, user)` — shows the `accrued` pending reward (struct) for a given token and user.

### Quick examples

Ethers.js: claim rewards for your address from a market

```js
const market = new ethers.Contract(MARKET_ADDRESS, MarketAbi, signer);
const tx = await market.redeemRewards(await signer.getAddress());
await tx.wait();
// the returned event/receipt will contain amounts corresponding to market.getRewardTokens()
```

Solidity (contract calling a market)

```solidity
IPMarket(marketAddress).redeemRewards(user);
```

Off-chain checks
- Check which tokens will be returned: call `market.getRewardTokens()`
- Inspect pending amounts per token: read `market.userReward(token, user).accrued` or call SY's `accruedRewards(user)` for SY-specific rewards.

### Calculating pending rewards from `activeBalance`

If you already know `activeBalance = market.activeBalance(user)` (the user's reward shares), you can compute pending rewards for each token using the same index math the contract uses.

High-level formula used on-chain (per token):

- indexNow = current global reward index for token (see below how to compute)
- userIndex = `market.userReward(token, user).index` (treat 0 as `INITIAL_REWARD_INDEX = 1`)
- deltaIndex = indexNow - userIndex
- rewardDelta = activeBalance * deltaIndex  (the project uses `mulDown` semantics)
- pending = `market.userReward(token, user).accrued` + rewardDelta

How to compute indexNow off-chain (matches `_updateRewardIndex`):

1. Read `rewardState(token)` from the market: gives `storedIndex` and `lastBalance`.
2. Let selfBal = `ERC20(token).balanceOf(marketAddress)`.
3. Include external tokens that would be redeemed by `_redeemExternalReward()`:
   - SY: call `SY.accruedRewards(marketAddress)` and add the entry for this token (if applicable).
   - PENDLE from gauge controller: include any pending PENDLE allocated to the market (if gauge controller expose a view). If you can't read this, conservatively omit it.
4. accrued = selfBal + syAccrued + pendingPendle - lastBalance
5. totalShares = `market.totalActiveSupply()` (if zero, index doesn't move).
6. indexBase = storedIndex == 0 ? 1 : storedIndex
7. indexNow = indexBase + floor(accrued / totalShares)  (use integer division rounding down)

Putting it together (per-token pseudocode):

```js
// tokens = await market.getRewardTokens();
const totalShares = await market.totalActiveSupply();
for (const token of tokens) {
  const { index: storedIndex, lastBalance } = await market.rewardState(token);
  const { index: userIndexRaw, accrued: userAccruedRaw } = await market.userReward(token, user);
  const selfBal = await ERC20(token).balanceOf(market.address);
  const syAccruedForToken = /* call SY.accruedRewards(market) and pick token slot if applicable */ 0;
  const pendingPendle = /* gauge controller pending PENDLE for market, if available */ 0;

  const accrued = selfBal.sub(lastBalance).add(syAccruedForToken).add(pendingPendle);
  const indexBase = storedIndex.eq(0) ? BigNumber.from(1) : storedIndex;
  let indexNow = indexBase;
  if (!totalShares.isZero() && accrued.gt(0)) {
    indexNow = indexNow.add(accrued.div(totalShares)); // divDown semantics
  }

  const userIndex = userIndexRaw.eq(0) ? BigNumber.from(1) : userIndexRaw;
  const deltaIndex = indexNow.sub(userIndex);
  const rewardDelta = activeBalance.mul(deltaIndex); // follow project's mulDown / fixed-point helpers
  const pending = userAccruedRaw.add(rewardDelta);
  // pending is the token amount you can expect from redeemRewards
}
```

Notes & tips:
- Be conservative: if you can't read SY.accruedRewards or gauge controller pending PENDLE, the computation using only `ERC20.balanceOf(market)` will reflect already-transferred tokens and is safe but may undercount soon-to-be-redeemed external rewards.
- The contract treats `storedIndex == 0` as `INITIAL_REWARD_INDEX = 1` — replicate that when computing `userIndex` and `indexNow`.
- All divisions use rounding-down semantics. Use the project's fixed-point helpers or integer floor division to match on-chain results exactly.
- `activeBalance` may be stale; the market updates `activeBalance` during reward redemption and token transfers. If you want to predict the value after a state change (transfer/mint/burn), simulate the activeBalance update first.

### Caveats & notes
- Boost uses a non-view ve helper on-chain to get current user ve balance. Off-chain view helpers (`balanceOf`) may be stale compared to what the gauge uses internally.
- Index maths uses project helpers (`mulDown` / `divDown`) — small rounding differences are expected.
- `activeBalance` is updated on specific state changes (e.g., token transfers, reward redemptions). If you query it off-chain it might be stale until an update call runs.
- The gauge caps active balance to the user's LP balance (no boost above your actual LP stake).

---

If you want I can also:
- add an example script (`scripts/claimRewards.js`) that queries `getRewardTokens()` and calls `redeemRewards`, or
- add a short section to `docs/vependle.md` linking to this page.

Document created from the implementation in `PendleGauge` / `PendleMarketV3` and `RewardManager`.
