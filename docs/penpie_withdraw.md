When calling `withdrawMarketWithClaim(_market, _amount, true)` on `PendleMarketDepositHelper` — what happens under the hood and every ERC‑20 transfer

This document traces the full call-path and lists all ERC‑20 transfers that may occur when `withdrawMarketWithClaim(_market, _amount, true)` is invoked on `PendleMarketDepositHelper` in this repo. It covers the helper → staking → master rewarder → rewarder interactions and highlights conditional branches that change which transfers occur.

## Quick summary (call flow)

User -> `PendleMarketDepositHelper.withdrawMarketWithClaim(_market, _amount, true)` (public)
- `PendleMarketDepositHelper.withdrawMarketWithClaim` calls `IPendleStaking.withdrawMarket(_market, msg.sender, _amount)` (external).
  - `IPendleStaking.withdrawMarket` is implemented in `PendleStakingBaseUpg.withdrawMarket` which calls `_harvestMarketRewards(_market, false)` (internal) to harvest Pendle market rewards, then burns the receipt token (`IMintableERC20.burn`) and transfers LP tokens back to the user (`IERC20.safeTransfer`).
  - After the withdraw completes, the helper calls `IMasterPenpie(masterpenpie).multiclaimFor(lps, rewards, user)` (external).
    - `MasterPenpie.multiclaimFor` delegates to `MasterPenpie._multiClaim` which calls `_claimBaseRewarder` / `_getRewardsFromRewarder` to invoke `IBaseRewardPool.getReward` or `getRewards` on rewarders (e.g., `BaseRewardPoolV2`, `StreamRewarder`).
    - `MasterPenpie._multiClaim` then sends `penpieOFT` (PNP) to the user via `MasterPenpie._sendPenpie` or queues to vlPenpie rewarder via `MasterPenpie._sendPenpieForVlPenpiePool`.

## Ordered ERC‑20 transfer trace (detailed)

Each transfer below is listed roughly in the order it may occur during the transaction. Some transfers are conditional (see notes). The actor shown is the contract that initiates or is the source of the transfer.

1) Harvest from Pendle market into PendleStaking
   - For each reward token T returned by `IPendleMarket(_market).getRewardTokens()` (queried by `PendleStakingBaseUpg._harvestMarketRewards`):
     - Transfer: T from Pendle Market -> `PendleStaking` (this contract)
     - Trigger: `IPendleMarket(_market).redeemRewards(address(this))` called from `PendleStakingBaseUpg._harvestMarketRewards`.
     - If a reward is native (NATIVE), the code maps it to `WETH` before accounting, so `PendleStaking` receives `WETH`.

2) PendleStaking splits/queues harvested tokens (implemented across `PendleStakingBaseUpg._sendRewards`, `_queueRewarder`, `_sendMPendleFees`)
   - If T == `PENDLE`:
     a) For every `feeInfo` (stored in the `pendleFeeInfos` array in `PendleStakingBaseUpg`):
        - `feeAmount` is computed inside `_sendRewards` (or `_sendMPendleFees` for mPendle fees).
        - If `feeInfo.isMPENDLE == false`:
          - If `feeInfo.isAddress == true`:
            - Transfer: `PENDLE` from `PendleStaking` -> `feeInfo.to`
            - Trigger: `IERC20(PENDLE).safeTransfer(feeInfo.to, feeTosend)` inside `PendleStakingBaseUpg._sendRewards`.
          - Else (`feeInfo.isAddress == false`):
            - `PendleStaking` approves `feeInfo.to` and calls `IBaseRewardPool(feeInfo.to).queueNewRewards(feeTosend, PENDLE)`.
            - Transfer: `PENDLE` from `PendleStaking` -> fee rewarder occurs when `BaseRewardPoolV2.queueNewRewards` (or other rewarder.queueNewRewards) executes `IERC20.safeTransferFrom(msg.sender, address(this), _amountReward)`; `msg.sender` is `PendleStaking`.
     b) Leftover `leftRewardAmount` is approved and queued to the pool rewarder via `_queueRewarder`:
        - `PendleStaking` -> pool rewarder: `PENDLE` (queued with `IBaseRewardPool.queueNewRewards`)

  - If T != `PENDLE`:
    a) If `autoBribeFee > 0` && `bribeManager` set && the bribe pool is active (checked via `IPenpieBribeManager`), `_sendRewards` will:
      - Transfer: T from `PendleStaking` -> `bribeManager` (via `IPenpieBribeManager.addBribeERC20` which ultimately pulls/transfers the token).
    b) Leftover `leftBonusBalance` is queued to the pool rewarder via `IBaseRewardPool.queueNewRewards` (or `StreamRewarder.queueNewRewards`):
      - Transfer: T from `PendleStaking` -> pool rewarder

3) If pool is marked `ismPendleRewardMarket[_market]` and reward token == `PENDLE` (handled in `_queueRewarder`):
   - `PendleStaking` converts `PENDLE` -> `mPendleOFT` using `_convertPendleTomPendle` (calls converter or `ISmartPendleConvert.smartConvert`):
     - Transfer: `PENDLE` from `PendleStaking` -> converter (after `safeApprove`)
     - Result: `mPendleOFT` credited to `PendleStaking`.
   - `PendleStaking` may send a portion of `mPendleOFT` to `mgpBlackHole` (burn) and emit `MPendleBurn`.
     - Transfer: `mPendleOFT` from `PendleStaking` -> `mgpBlackHole` (if configured)
   - Remaining `mPendleOFT` is queued to the rewarder via `IBaseRewardPool.queueNewRewards`:
     - Transfer: `mPendleOFT` from `PendleStaking` -> pool rewarder

4) `PendleStaking._sendMPendleFees` (conversion + distribution)
   - `PendleStaking` converts a tracked `PENDLE` amount to `mPendleOFT` using `_convertPendleTomPendle`.
   - For each `pendleFeeInfos` entry with `isMPENDLE == true`:
     - If `isAddress == true`: `IERC20(mPendleOFT).safeTransfer(feeInfo.to, amount)` — Transfer `mPendleOFT` from `PendleStaking` -> fee address.
     - Else: approve and call `IBaseRewardPool(feeInfo.to).queueNewRewards(amount, mPendleOFT)` — Transfer `mPendleOFT` from `PendleStaking` -> fee rewarder.

5) (Optional in batch path) `PendleStaking._harvestBatchMarketRewards` may pay a harvest caller in ETH via `ETHZapper`:
  - `PendleStaking` approves and transfers `PENDLE` to `ETHZapper` via `IETHZapper.swapExactTokensToETH`.
  - Transfer: `PENDLE` from `PendleStaking` -> `ETHZapper` (then `ETHZapper` swaps and sends ETH native to the caller). Note: ETH output is native, not an ERC‑20.

6) Withdraw LP token to user (core withdraw) — implemented in `PendleStakingBaseUpg.withdrawMarket`
  - `IMintableERC20(poolInfo.receiptToken).burn(_for, _amount)` (receipt burn; some receipt implementations emit `Transfer(..., address(0), amount)`).
  - Transfer: market LP token (the `_market` LP) from `PendleStaking` -> user.
  - Trigger: `IERC20(poolInfo.market).safeTransfer(_for, _amount)` inside `PendleStakingBaseUpg.withdrawMarket`.

7) `MasterPenpie.multiclaimFor` flow (Helper calls `MasterPenpie.multiclaimFor(lps, rewards, user)`)
   - `MasterPenpie._multiClaim` updates pool accounting (`updatePool`) and computes `claimablePenpie`, then calls `_claimBaseRewarder` which calls `_getRewardsFromRewarder`.
     - `_getRewardsFromRewarder` will call `IBaseRewardPool.getRewards(_account, _receiver, _rewardTokens)` when `_rewardTokens.length > 0`, otherwise `IBaseRewardPool.getReward(_account, _receiver)`.
     - In `BaseRewardPoolV2.getReward` / `getRewards`, for each reward token the user earned, the rewarder calls `_sendReward`:
       - Transfer: reward token X from rewarder -> user (via `IERC20.safeTransfer` inside `BaseRewardPoolV2._sendReward` or `StreamRewarder._sendReward`).
   - After rewarders are processed, `MasterPenpie._multiClaim` sends PNP (penpieOFT):
     - For default pools: `MasterPenpie._sendPenpie(_user, _receiver, amount)` performs `penpieOFT.safeTransfer(_receiver, amount)` — Transfer `penpieOFT` from `MasterPenpie` -> user.
     - For vlPenpie pools: `MasterPenpie._sendPenpieForVlPenpiePool` approves vlPenpie rewarder and calls `IVLPenpieBaseRewarder.queuePenpie(...)` — Transfer `penpieOFT` from `MasterPenpie` -> vlPenpie rewarder.

## Approvals (non-transfer on-chain actions you will see)
- `PendleStakingBaseUpg` calls `IERC20(...).safeApprove(_rewarder, amount)` prior to `IBaseRewardPool.queueNewRewards` or `IPenpieBribeManager.addBribeERC20`. Rewarders then call `safeTransferFrom(msg.sender, address(this), _amount)` in their `queueNewRewards` implementations (e.g., `BaseRewardPoolV2.queueNewRewards`, `StreamRewarder.queueNewRewards`).
- `MasterPenpie` may call `penpieOFT.safeApprove(vlPenpieRewarder, _amount)` before `IVLPenpieBaseRewarder.queuePenpie` (see `MasterPenpie._sendPenpieForVlPenpiePool`).

## Notes about burning / ERC‑20 "transfer to 0x0"
- `IMintableERC20(...).burn(...)` reduces receipt token supply. Depending on the receipt token implementation it may emit a Transfer event to address(0). The trace above treats burning separately from explicit safeTransfer operations.

## Conditional branches that change which tokens move
- The set of reward tokens depends on `IPendleMarket(_market).getRewardTokens()` (market specific). Only those tokens are harvested initially.
- If a bonus token is `PENDLE`, special fee splitting + possible conversion to `mPendleOFT` apply.
- `autoBribeFee` + `bribeManager` configured + pool active -> non‑PENDLE tokens partially go to bribe manager.
- `ismPendleRewardMarket[_market]` true -> PENDLE harvests are converted to `mPendleOFT` before queued to rewarder (and part may be burned to `mgpBlackHole`).
- If you call `withdrawMarketWithClaim(..., false)`, only the LP token transfer (PendleStaking -> user) happens; multiclaim / rewarder → user transfers do not execute.

## Where transfers originate (condensed)
- Pendle Market -> PendleStaking: harvested reward tokens (via `redeemRewards`)
- PendleStaking -> (fee addresses / bribeManager / rewarders): various reward tokens (PENDLE, mPendleOFT, non‑PENDLE tokens)
- PendleStaking -> user: LP token returned on withdraw
- Rewarder -> user: claimed bonus tokens when `MasterPenpie` calls `getReward`/`getRewards`
- MasterPenpie -> user (or vlPenpie rewarder): penpieOFT (PNP)

## How to verify in a test / live run
- To see the exact transfers for a given market on-chain, you can:
  1) Inspect `IPendleMarket(_market).getRewardTokens()` to know which tokens will be harvested.
  2) Inspect `PendleStaking` config: `pendleFeeInfos`, `autoBribeFee`, `ismPendleRewardMarket[_market]`, `bribeManager`, `rewarder` addresses.
  3) Run a test (Hardhat / Forge) that: deposit, ensure the user has receipt tokens, call `withdrawMarketWithClaim(..., true)` and capture Transfer events logs in the transaction receipt — they will appear in chronological order.

If you want I can scaffold a small Forge/Hardhat test that executes `withdrawMarketWithClaim` against a local deployment or mock contracts and prints the transfer events in order.

---

Generated from repo analysis on: 2025-10-08
Sources referenced: `vendor/penpie_contracts/pendle/PendleMarketDepositHelper.sol`, `vendor/penpie_contracts/pendle/PendleStakingBaseUpg.sol`, `vendor/penpie_contracts/rewards/MasterPenpie.sol`, `vendor/penpie_contracts/rewards/BaseRewardPoolV2.sol`, `vendor/penpie_contracts/rewards/StreamRewarder.sol`.
