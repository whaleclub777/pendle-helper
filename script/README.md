Deploy scripts for SharedVePendle

Files
- `DeploySharedVePendle.s.sol` — Foundry/Forge Solidity script for local testing. Deploys Mock PENDLE, MockVotingEscrow, MockVotingController and then `SharedVePendle`.
- `deploy_shared_ve_pendle.ts` — Node/ethers script for environment-driven deploys (mainnet/testnet). Reads addresses from `.env`.

Running the Foundry script (recommended for local tests)

1. Start anvil (or use `forge test`'s built-in node):

```bash
anvil -m "test test test test test test test test test test test junk" &
```

2. Broadcast the script with forge:

```bash
export PRIVATE_KEY=0xabc...   # or set in CI
forge script script/DeploySharedVePendle.s.sol:DeploySharedVePendle --fork-url https://rpc.yournet --private-key $PRIVATE_KEY --broadcast -vvvv
```

Setting the sender / signing key

By default Forge will use its configured default sender when broadcasting. For deterministic deploys and to avoid using the default account, set an explicit sender or private key.

- Use `--sender <ADDRESS>` to set the transaction "from" address (useful when the node has unlocked accounts).
- Use `--private-key <KEY>` to sign transactions with a specific private key. This is the most common and secure option for CI or remote RPCs.
