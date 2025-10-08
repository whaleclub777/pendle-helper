# Penpie rewarder — what it is and how it works

This document summarizes the role and mechanics of a "rewarder" in the Penpie (Magpie) codebase and points to the concrete implementations in this repository.

## What is a rewarder?
A rewarder is a per‑pool contract that receives bonus reward tokens (tokens other than the main PNP / Penpie emission) and manages their bookkeeping and distribution to stakers of a pool. Rewarders hold tokens that are queued by the staking/harvest logic and only transfer tokens to users when the MasterPenpie contract requests claims.

Rewarders do NOT mint main PNP emissions — MasterPenpie handles PNP creation and distribution. Rewarders only manage bonus tokens and payouts.

## Common rewarder implementations
- `BaseRewardPoolV2` — standard rewarder that supports multiple bonus tokens, immediate per‑token accounting (rewardPerToken) and queuedRewards when total stake is zero.
- `StreamRewarder` — streams queued rewards over a configured `duration` using `rewardRate` / `periodFinish` so rewards are disbursed over time.
- Specialized variants (e.g., `vlPenpieBaseRewarder`, `mPendleSVBaseRewarder`, `ARBRewarder`, `VlStreamRewarder`) extend the above behaviors for specific pools or special token handling.

Files in this repo: `vendor/penpie_contracts/rewards/BaseRewardPoolV2.sol`, `vendor/penpie_contracts/rewards/StreamRewarder.sol`, and other files in `vendor/penpie_contracts/rewards/`.

## Lifecycle and call flow (concise)
1. Pool creation: `MasterPenpie.createRewarder(...)` (via `ERC20FactoryLib.createRewarder`) deploys a `BaseRewardPoolV2` or other rewarder and associates it with a pool's receipt token.
2. Funding / queueing rewards:
   - `PendleStakingBaseUpg` (or other managers) computes harvested / leftover amounts and calls `_queueRewarder(...)` which does:
     - `IERC20(token).safeApprove(rewarder, amount)` then
     - `IBaseRewardPool(rewarder).queueNewRewards(amount, token)`.
   - Rewarder pulls tokens with `safeTransferFrom(msg.sender, address(this), amount)` and updates internal accounting.
3. Accounting inside rewarder:
   - `BaseRewardPoolV2` tracks `rewardPerTokenStored`, `queuedRewards`, per‑reward token `UserInfo` entries and computes earned amounts using receipt token supply/decimals.
   - `StreamRewarder` computes `rewardRate` and streams tokens over `duration` using `periodFinish` and `rewardPerToken` math.
4. Claiming / Payout:
   - `MasterPenpie` calls `IBaseRewardPool.getReward(user, receiver)` or `getRewards(...)` during its multi‑claim flow.
   - Rewarder updates per‑user accounting and `safeTransfer`s the earned tokens to the requested receiver. `getReward` / `getRewards` are restricted by `onlyMasterPenpie`.

## Key functions & modifiers
- `queueNewRewards(uint256 _amount, address _rewardToken)` — deposit tokens into rewarder (only callable by allowed reward queuers). Rewarder pulls the token and updates queued/distribution state.
- `getReward(address _account, address _receiver)` / `getRewards(...)` — called by `MasterPenpie` to pay out all (or selected) reward tokens to a receiver.
- `donateRewards(...)` — allow donating to a registered reward token.
- Modifiers: `onlyRewardQueuer` / `onlyMasterPenpie` (protect queueing & claiming).

## Important behaviors & edge cases
- If total staked (receipt token totalSupply) == 0, incoming tokens are added to `queuedRewards` and distributed later when there is stake.
- Reward tokens can be added dynamically when first queued.
- Accounting normalizes by receipt token decimals — precision matters for rewardPerToken math.
- Only authorized reward queuers may call `queueNewRewards` and only `MasterPenpie` may call claim functions.

## Where to look in this repo (reference)
- Rewarder implementations: `vendor/penpie_contracts/rewards/BaseRewardPoolV2.sol`, `vendor/penpie_contracts/rewards/StreamRewarder.sol`, others in `vendor/penpie_contracts/rewards/`
- Factory / creation: `vendor/penpie_contracts/libraries/ERC20FactoryLib.sol`, `vendor/penpie_contracts/rewards/MasterPenpie.sol` (`createRewarder`)
- Queuing from staking / harvest: `vendor/penpie_contracts/pendle/PendleStakingBaseUpg.sol` (`_sendRewards`, `_queueRewarder`)
- Interface: `vendor/penpie_contracts/interfaces/IBaseRewardPool.sol`

## FAQ (brief)
- Who funds rewarders? Typically `PendleStaking` or other authorised managers: they approve and call `queueNewRewards`.
- When are rewards delivered? When `MasterPenpie` calls `getReward` / `getRewards` (e.g., during user withdraws or multiclaim flows).
- Do rewarders mint tokens? No — they hold and transfer existing tokens that were transferred in.

---

If you'd like, I can add a small sequence diagram or extract and document the exact math for `rewardPerToken` in `BaseRewardPoolV2` and `StreamRewarder`. Want that included?
