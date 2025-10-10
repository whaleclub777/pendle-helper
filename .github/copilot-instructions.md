# Copilot / AI Agent Instructions — pendle-helper

These notes are a compact, actionable reference so an AI coding agent can be immediately productive in this repository.

Overview
- This repo contains two main parts: Solidity smart contracts (root `src/`, tests in `test/`) and a Vue 3 dapp in `dapp/`.
- Contracts are developed and tested with Foundry (forge, anvil, cast). The dapp is a Vite + Vue 3 TypeScript app under `dapp/`.

High-level architecture & important files
- Core contracts: `src/SharedVePendle.sol`, `src/SharedVePendleFactory.sol`. Read these first to understand the reward accounting and ownership model.
- Interfaces: `src/interfaces/` (voting controller, voting escrow, Pendle Market) — the contracts talk to external systems through these interfaces.
- Tests: `test/*.t.sol` and `test/mocks/*` are canonical examples of how the contracts are expected to behave. Mocks model VE, markets and reward flows.
- Dapp: `dapp/src/` (Vue) is a separate workspace. Router currently at `dapp/src/router/index.ts` and main UI at `dapp/src/App.vue`.

Key patterns & behaviors to preserve (do not change without tests)
- Multi-market accounting: markets are stored in a mapping to a MarketInfo struct. Reward tokens for a market are snapshotted when `addMarket` is called and treated as immutable afterwards. See `_addMarket` and `MarketInfo.rewardTokens` in `SharedVePendle.sol`.
- Lazy reward harvesting: rewards are pulled (redeemRewards) and distributed when mutating actions occur (deposit/withdraw/claim). If `totalLp == 0`, harvested rewards are stored in `unallocatedRewards` until the next harvest.
- Reward distribution math: uses `ACC_PRECISION = 1e12` and `accRewardPerShare` patterns. Keep precision intact.
- PENDLE fee logic: when a reward token equals PENDLE the contract charges a fee (bps) and accumulates it in `pendleFees`. Owner redeems via `ownerRedeem()`; tests assume 5% example (see tests).
- Owner semantics: constructor uses `Ownable(msg.sender)` (non-standard pattern). Tests rely on the caller of the constructor becoming owner (the test contract). Be mindful when changing ownership initialization.
- Storage vs memory: many internal helpers return `MarketInfo storage` pointers. Follow existing storage access patterns to avoid subtle bugs with nested mappings.

Developer workflows (commands)
- Install root workspace (pnpm):
  - pnpm install
- Build + test contracts (foundry) from repo root:
  - forge build
  - forge test
  - anvil (run a local node for manual scripts)
  - forge snapshot (gas snapshots)
- Dapp (from repo root or `dapp/`):
  - cd dapp && pnpm install
  - pnpm dev (start vite dev server)
  - pnpm build (production build)
  - pnpm test:unit (run vitest unit tests)
  - pnpm type-check (vue-tsc --build)

Important repo conventions
- Solidity version pinned to ^0.8.17. Keep pragma consistent across new files.
- Local libs are vendored under `lib/` and referenced via remappings (`remappings.txt`) — don't remove or duplicate dependencies without updating remappings and `foundry.toml`.
- Tests use Forge's `vm` helpers (`vm.prank`, `vm.warp`, etc.). When writing new tests follow existing style in `test/*.t.sol` and place mocks in `test/mocks/`.
- Use SafeERC20 for transfers; the code uses `forceApprove` in constructors for long-lived approvals.

What to look at when changing behavior
- If you modify reward accounting, update tests in `test/RewardingMockPendleMarket.sol` and `test/SharedVePendle.t.sol` — they cover harvest/unallocated flows and fees.
- If adding a new public API, add a corresponding Forge test that constructs mocks and exercises multi-market flows (depositLp, claimRewards, withdrawLp).
- For dapp changes, run `pnpm test:unit` and `pnpm dev` to validate behavior; components expect router/pinia stores in `dapp/src/stores/`.

Quick code examples (patterns to mirror)
- Snapshot reward tokens on addMarket: see `SharedVePendle._addMarket`.
- Harvest and distribute:
  - call `IPendleMarket(market).redeemRewards(address(this))` in try/catch,
  - compute delta of balances and if `totalLp == 0` increment `unallocatedRewards`, else update `accRewardPerShare`.
- Settling a user: compute gross = (userBal * acc) / ACC_PRECISION, transfer net and update `rewardDebt`.

Where to find more context
- Foundry config: `foundry.toml` (libs, out dir and fmt settings).
- Remappings: `remappings.txt` and `lib/` folder for vendored contracts.
- Dapp config & scripts: `dapp/package.json`, `dapp/vite.config.ts`.

If anything is unclear or a section above is incomplete, tell me which part you'd like expanded (examples, commands, or specific files) and I will iterate.

- we use unocss for styling, with preset-wind4
