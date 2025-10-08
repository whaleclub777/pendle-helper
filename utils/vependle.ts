import { createPublicClient, http, type Address, type PublicClient } from 'viem';

// Minimal ABIs containing only the functions we need
const IP_VE_TOKEN_ABI = [
  {
    name: 'totalSupplyCurrent',
    type: 'function',
    stateMutability: 'nonpayable',
    outputs: [{ type: 'uint128' }],
    inputs: [],
  },
  {
    name: 'totalSupplyStored',
    type: 'function',
    stateMutability: 'view',
    outputs: [{ type: 'uint128' }],
    inputs: [],
  },
  {
    name: 'totalSupplyAndBalanceCurrent',
    type: 'function',
    stateMutability: 'nonpayable',
    outputs: [{ type: 'uint128' }, { type: 'uint128' }],
    inputs: [{ name: 'user', type: 'address' }],
  },
];

const VL_PENPIE_ABI = [
  {
    name: 'totalLocked',
    type: 'function',
    stateMutability: 'view',
    outputs: [{ type: 'uint256' }],
    inputs: [],
  },
  {
    name: 'totalSupply',
    type: 'function',
    stateMutability: 'view',
    outputs: [{ type: 'uint256' }],
    inputs: [],
  },
];

/**
 * Create a viem PublicClient from an RPC url (helper)
 */
function clientFromRpc(rpcUrl: string) {
  return createPublicClient({ transport: http(rpcUrl) });
}

/**
 * Get the current total vePENDLE supply by calling `totalSupplyCurrent()`.
 * Note: this function calls a non-view helper on-chain via eth_call to get an up-to-date
 * snapshot of total supply. It returns a bigint representing the raw token units.
 *
 * @param clientOrRpc either a viem PublicClient or an rpc url string
 * @param veAddress the voting-escrow contract address (vePENDLE)
 */
export async function getVePendleTotalCurrent(
  clientOrRpc: PublicClient | string,
  veAddress: Address
): Promise<bigint> {
  const client = typeof clientOrRpc === 'string' ? clientFromRpc(clientOrRpc) : clientOrRpc;

  try {
    const res = await client.readContract({
      address: veAddress,
      abi: IP_VE_TOKEN_ABI,
      functionName: 'totalSupplyCurrent',
    });
    // viem returns bigint for integer solidity outputs
    return res as bigint;
  } catch (err: any) {
    // Bubble up a clearer error
    throw new Error(`failed to read totalSupplyCurrent from ve contract ${veAddress}: ${err?.message ?? err}`);
  }
}

/**
 * Get the total Penpie locked reported by the `VLPenpie` contract via `totalLocked()`.
 * Returns a bigint representing raw token units.
 *
 * @param clientOrRpc either a viem PublicClient or an rpc url string
 * @param vlPenpieAddress the vlPenpie contract address
 */
export async function getPenpieTotalLocked(
  clientOrRpc: PublicClient | string,
  vlPenpieAddress: Address
): Promise<bigint> {
  const client = typeof clientOrRpc === 'string' ? clientFromRpc(clientOrRpc) : clientOrRpc;

  try {
    const res = await client.readContract({
      address: vlPenpieAddress,
      abi: VL_PENPIE_ABI,
      functionName: 'totalLocked',
    });
    return res as bigint;
  } catch (err: any) {
    throw new Error(`failed to read totalLocked from vlPenpie ${vlPenpieAddress}: ${err?.message ?? err}`);
  }
}

/**
 * Convenience helper that fetches both vePENDLE total (current) and vlPenpie locked amount.
 * Returns an object with { veTotal, penpieLocked } as bigints.
 */
export async function getVeAndPenpieTotals(
  clientOrRpc: PublicClient | string,
  veAddress: Address,
  vlPenpieAddress: Address
): Promise<{ veTotal: bigint; penpieLocked: bigint }> {
  const client = typeof clientOrRpc === 'string' ? clientFromRpc(clientOrRpc) : clientOrRpc;

  // Parallelize the two reads
  const [veTotal, penpieLocked] = await Promise.all([
    getVePendleTotalCurrent(client, veAddress),
    getPenpieTotalLocked(client, vlPenpieAddress),
  ]);

  return { veTotal, penpieLocked };
}

// Example usage (commented):
// import { getVeAndPenpieTotals } from './utils/vependle';
const rpc = 'https://mainnet.infura.io/v3/YOUR_KEY';
const ve = '0x...';
const vl = '0x...';
const { veTotal, penpieLocked } = await getVeAndPenpieTotals(rpc, ve as Address, vl as Address);
console.log({ veTotal: veTotal.toString(), penpieLocked: penpieLocked.toString() });
