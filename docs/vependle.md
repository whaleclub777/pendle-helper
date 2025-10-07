# vePENDLE — Quick reference

This short doc shows how vePENDLE (the voting-escrow token) is represented in the codebase, example JSON-RPC / ethers.js calls you can run to inspect or simulate actions, and a flow diagram showing how locks → ve balance → broadcasts → gauge consumption connect.

## Key contracts & functions
- Voting-escrow implementation (mainchain): `lib/pendle-core-v2-public/contracts/LiquidityMining/VotingEscrow/VotingEscrowPendleMainchain.sol`
  - increase lock: `increaseLockPosition(uint128 additionalAmountToLock, uint128 newExpiry)`
  - broadcast: `broadcastUserPosition(address user, uint256[] chainIds)`, `broadcastTotalSupply(uint256[] chainIds)`
  - snapshot/update: `totalSupplyCurrent()`
  - withdraw: `withdraw()`
- Offchain/static helper: `lib/pendle-core-v2-public/contracts/offchain-helpers/router-static/base/ActionVePendleStatic.sol`
  - view simulation: `increaseLockPositionStatic(address user, uint128 additionalAmountToLock, uint128 newExpiry) returns (uint128 newVeBalance)`
- Interface: `lib/pendle-core-v2-public/contracts/interfaces/IPVeToken.sol`
  - `balanceOf(address) view returns (uint128)`
  - `positionData(address) view returns (uint128 amount, uint128 expiry)`
  - `totalSupplyStored() view returns (uint128)`
  - `totalSupplyCurrent() returns (uint128)`
  - `totalSupplyAndBalanceCurrent(address user) returns (uint128, uint128)`

> Note: `totalSupplyCurrent()` and `totalSupplyAndBalanceCurrent(...)` are not declared `view` because they update internal slope/supply bookkeeping; you can still `eth_call` them to simulate and read returned values without sending a state-changing transaction.

---

## Example 1 — ethers.js (Node) script
This example uses `ethers` to call `increaseLockPositionStatic`, `totalSupplyCurrent`, and `totalSupplyAndBalanceCurrent` from a JSON-RPC endpoint.

Save as `scripts/vependle-queries.js` (example):

```js
// Requires: npm install ethers
const { ethers } = require('ethers');

// Replace these placeholders
const RPC_URL = process.env.RPC_URL || 'https://mainnet.infura.io/v3/YOUR_KEY';
const ACTION_STATIC_ADDR = '0xYourActionStaticContractAddress'; // e.g. deployed ActionVePendleStatic
const VE_ADDR = '0xYourVePendleAddress';
const EXAMPLE_USER = '0xUserAddress';

// Minimal ABIs (only the functions we call)
const actionStaticAbi = [
  'function increaseLockPositionStatic(address user, uint128 additionalAmountToLock, uint128 newExpiry) view returns (uint128)'
];
const veAbi = [
  'function totalSupplyCurrent() returns (uint128)',
  'function totalSupplyAndBalanceCurrent(address user) returns (uint128, uint128)'
];

async function main() {
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);

  const actionStatic = new ethers.Contract(ACTION_STATIC_ADDR, actionStaticAbi, provider);
  const ve = new ethers.Contract(VE_ADDR, veAbi, provider);

  // Example: simulate increasing the lock for EXAMPLE_USER
  const additionalAmount = ethers.BigNumber.from('1000000000000000000'); // 1 PENDLE (assuming 18 decimals)
  // newExpiry must be a valid week timestamp (WeekMath aligned). Example: a unix timestamp in the future.
  const newExpiry = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 7 * 26; // ~26 weeks from now (simple example)

  console.log('Calling increaseLockPositionStatic...');
  const newVeBalance = await actionStatic.increaseLockPositionStatic(EXAMPLE_USER, additionalAmount, newExpiry);
  console.log('Estimated new ve balance (uint128):', newVeBalance.toString());

  console.log('\nCalling totalSupplyCurrent (simulated call)...');
  const totalSupply = await ve.totalSupplyCurrent();
  console.log('totalSupplyCurrent():', totalSupply.toString());

  console.log('\nCalling totalSupplyAndBalanceCurrent(user)...');
  const [supply, balance] = await ve.totalSupplyAndBalanceCurrent(EXAMPLE_USER);
  console.log('supply:', supply.toString(), 'userBalance:', balance.toString());
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
```

Notes:
- `increaseLockPositionStatic` is a view call implemented by the offchain helper `ActionVePendleStatic` — it's safe to call from the frontend to estimate the resulting ve balance before sending transactions.
- `totalSupplyCurrent()` updates slope changes in the mainchain contract; when called via `eth_call` it runs the same logic in a simulated environment and returns the computed value.

---

## Example 2 — raw JSON-RPC `eth_call` (curl)
If you want to call the functions via raw RPC, you can do an `eth_call` with the function selector + encoded params. The easiest way to build the `data` payload is via ethers/web3 in a short script and then copy it to curl. Below are example steps.

1) Build calldata using ethers (Node REPL or script):

```js
const { ethers } = require('ethers');
const veInterface = new ethers.utils.Interface(['function totalSupplyAndBalanceCurrent(address user) returns (uint128, uint128)']);
const calldata = veInterface.encodeFunctionData('totalSupplyAndBalanceCurrent', ['0xYourUserAddress']);
console.log(calldata);
```

2) Use `curl` to call `eth_call` (replace placeholders):

```bash
curl -s -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"0xYourVePendleAddress","data":"0xENCODED_CALLDATA_HERE"}, "latest"]}' \
  https://mainnet.infura.io/v3/YOUR_KEY
```

The returned result is raw hex; decode it using `ethers.utils.defaultAbiCoder.decode(['uint128','uint128'], hexResult)` or via an ABI decoder.

---

## Diagram — flow (lock → ve math → broadcasts → gauge consumption)

```mermaid
flowchart LR
  subgraph User
    U[User] -->|lock PENDLE| VEContract[VotingEscrow (vePENDLE)]
  end

  VEContract -->|stores LockedPosition| Locked[LockedPosition(amount, expiry)]
  VEContract -->|maintains| Slope[slopeChanges & weekly snapshots]
  Locked -->|convertToVeBalance| VeBal[VeBalance(bias, slope)]
  VeBal -->|contributes to| Total[Total ve supply (_totalSupply)]

  Total -->|broadcast| CrossChain[Cross-chain broadcast]
  VEContract -->|broadcastUserPosition / broadcastTotalSupply| CrossChain

  Total -->|queried by| Gauge[PendleGauge]
  VeBal -->|queried by| Gauge
  Gauge -->|computes| Boost[ve-boosted LP active balance]
  Boost -->|determines| Rewards[Rewards distribution]

  classDef contract fill:#f9f,stroke:#333,stroke-width:1px
  class VEContract,Slope,Locked,VeBal,Total contract
```

Notes on the diagram:
- `convertToVeBalance` is implemented in `lib/pendle-core-v2-public/contracts/LiquidityMining/libraries/VeBalanceLib.sol` (slope = amount / MAX_LOCK_TIME, bias = slope * expiry).
- `totalSupplyCurrent()` processes `slopeChanges` week-by-week to update `_totalSupply` and writes `totalSupplyAt[wTime]` snapshots.
- Gauges call `totalSupplyAndBalanceCurrent(user)` to get an up-to-date supply and the user's current ve balance and compute tokenless/ve-boosted shares.

---

## Quick checklist for frontends / scripts
- To show users how much ve they'd get before sending a tx: call `increaseLockPositionStatic(...)` on the `lib/pendle-core-v2-public/contracts/offchain-helpers/router-static/base/ActionVePendleStatic.sol` helper (view-only).
- To show up-to-date global supply and user ve (as the contract would compute it): call `totalSupplyAndBalanceCurrent(user)` via `eth_call` (or via ethers contract call).
- When broadcasting to other chains, the caller must provide ETH to pay the cross-chain message fee; destination contracts must be configured on the ve contract (owner-only).

---

If you'd like, I can also:
- Add a tiny helper script that encodes calldata for `eth_call` (so you can copy-paste the `data` field into curl),
- Or generate a short `README` snippet that lists the actual deployed `vePendle` addresses from `lib/pendle-core-v2-public/deployments/*.json` into a small table.

Pick one and I'll add it next.
