## How `PendleStakingBaseUpg` splits fees

This document explains how `PendleStakingBaseUpg` (see `vendor/penpie_contracts/pendle/PendleStakingBaseUpg.sol`) computes and routes fees when Pendle rewards are harvested.

### Quick summary
- Harvested reward tokens are received by `PendleStaking` and processed by `_sendRewards(...)`.
- If the reward token is `PENDLE`, the contract splits configured `pendleFeeInfos` out of the original amount. Some fee entries are paid immediately as PENDLE; others are kept and later converted to `mPendleOFT` and distributed.
- Non‑PENDLE tokens can pay an `autoBribeFee` to `bribeManager`; the remainder is queued to the pool rewarder.
- Conversions PENDLE->mPendle and optional mPendle burns are handled in `_sendMPendleFees(...)` and `_queueRewarder(...)`.

### Key variables and concepts
- DENOMINATOR = 10000 (basis for percentage math).
- `pendleFeeInfos[]` — array of Fees: `{ value, to, isMPENDLE, isAddress, isActive }`.
  - `value` is in basis points (out of `DENOMINATOR`).
  - `isMPENDLE`: true means the fee should be paid in `mPendleOFT` (converted later).
  - `isAddress`: true => transfer to a raw address, false => destination is a rewarder contract and the code uses `queueNewRewards`.
- `autoBribeFee` — basis points (DENOMINATOR) applied to non‑PENDLE tokens when bribe manager and pool active.
- `mPendleOFT`, `mPendleConvertor`, `smartPendleConvert` — used to convert PENDLE -> mPendle.
- `mgpBlackHole`, `mPendleBurnRatio` — optional burn of a portion of mPendle before queuing.

### PENDLE fee split (detailed)
1) For a PENDLE reward with `_originalRewardAmount`:
   - For each `feeInfo` where `feeInfo.isActive`:
     - feeAmount = (_originalRewardAmount * feeInfo.value) / DENOMINATOR
     - The contract decreases `leftRewardAmount` by feeAmount.
     - If `feeInfo.isMPENDLE == false`:
       - If `feeInfo.isAddress == true`: `IERC20(PENDLE).safeTransfer(feeInfo.to, feeAmount)`
       - Else: `safeApprove` then `IBaseRewardPool(feeInfo.to).queueNewRewards(feeAmount, PENDLE)` (rewarder pulls tokens).
     - If `feeInfo.isMPENDLE == true`: the PENDLE amount is NOT transferred now — it's retained and later converted to `mPendleOFT`.
   - After processing fees, the remaining `_leftRewardAmount` is queued to the pool rewarder via `_queueRewarder(...)`.
     - If `ismPendleRewardMarket[_market]` is true the leftover PENDLE is converted to `mPendleOFT`, an optional burn is sent to `mgpBlackHole`, and the remainder queued.

2) After harvest loops the contract calls `_sendMPendleFees(pendleForMPendleFee)` where `pendleForMPendleFee` is computed from actual PENDLE balance changes.
   - `_sendMPendleFees` converts the provided PENDLE to mPendle using `smartPendleConvert` (if set) or `mPendleConvertor`.
   - It computes `totalmPendleFees` = sum of `feeInfo.value` for active entries with `isMPENDLE == true`.
     - If `totalmPendleFees == 0` it returns early.
   - For each `feeInfo` with `isMPENDLE && isActive`:
     - amount = mPendleFeesToSend * feeInfo.value / totalmPendleFees
     - If `isAddress`: transfer `mPendleOFT` to `feeInfo.to`.
     - Else: approve + `IBaseRewardPool(feeInfo.to).queueNewRewards(amount, mPendleOFT)`.
   - Note: mPendle recipients are split proportionally among only the MPENDLE-marked entries (normalized by the sum of their `value` fields), not by `DENOMINATOR`.

### Non‑PENDLE tokens
- If `_rewardToken != PENDLE` and `autoBribeFee > 0` and `bribeManager` is set and pool active:
  - autoBribeAmount = (_originalRewardAmount * autoBribeFee) / DENOMINATOR is approved and sent to `bribeManager` via `addBribeERC20`.
  - The remainder is queued to the pool rewarder.
- If `autoBribeFee == 0` or `bribeManager` unset/inactive, the full token amount goes to the rewarder.

### Approvals and mechanics
- Transfers to addresses: `IERC20(...).safeTransfer(...)`.
- When sending to rewarders the contract `safeApprove(...)` then calls `queueNewRewards(...)`; rewarders typically call `safeTransferFrom(msg.sender, address(this), _amount)` to pull tokens.
- For bribe manager the contract approves and calls `addBribeERC20` (manager pulls or handles tokens).

### Edge cases & important notes
- fee entries with `isActive == false` are skipped.
- PENDLE portions tagged `isMPENDLE == true` are not sent immediately; they're converted and distributed later as mPendle.
- `_sendMPendleFees` returns early if there are no MPENDLE fee entries.
- `totalPendleFee` is validated by setters to never exceed `DENOMINATOR`.
- `ismPendleRewardMarket[_market]` changes the behavior: leftovers are converted to `mPendleOFT` and optionally burned to `mgpBlackHole`.

### Short numeric example
Assume DENOMINATOR = 10000 and a single PENDLE harvest = 1,000 PENDLE with two fee entries:
- Fee A: `value = 200` (2%), `isMPENDLE = false`, `isAddress = true`
- Fee B: `value = 100` (1%), `isMPENDLE = true`, `isAddress = false`

Calculations:
- Fee A = 1000 * 200 / 10000 = 20 PENDLE → transferred immediately to Fee A address.
- Fee B = 1000 * 100 / 10000 = 10 PENDLE → retained for conversion to mPendle later.
- leftRewardAmount = 1000 - 20 - 10 = 970 → queued to rewarder (or converted to mPendle first if `ismPendleRewardMarket`).
- Later `_sendMPendleFees` converts the 10 PENDLE to, e.g., 10 mPendle and because it's the only MPENDLE entry it receives the entire 10 mPendle (queued or transferred as configured).

### Where to look in code
- `_sendRewards(...)`, `_queueRewarder(...)`, `_sendMPendleFees(...)`, `_convertPendleTomPendle(...)` in `vendor/penpie_contracts/pendle/PendleStakingBaseUpg.sol`.

---

If you want, I can also generate a small Forge test that mints mock harvest tokens and asserts the exact transfers and approvals that occur for a chosen configuration.
