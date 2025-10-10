<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import type { Abi, Hash } from 'viem'
import { writeContract, readContract } from '@wagmi/core'
import { useProvider, config } from '../lib/provider'
import { useState } from '../lib/state'
// Import full contract ABI JSON (includes all functions/events)
// Keep outside src/ might still work, but we are inside src/components so relative path is ../../assets
import ABIJson from '../../assets/abi.json'
import TransactionList from './TransactionList.vue'

// Cast imported JSON to a viem Abi type (read-only)
const ABI = ABIJson as Abi

const provider = useProvider()
const store = useState()
const amount = ref<string>('0')
const expiry = ref<string>('0')
const toAddress = ref('')
const ownerAddress = ref<string | null>(null)
const veBalance = ref<string | null>(null)
const pendingTxs = ref<Hash[]>([])

function ensureAddress(addr: string): addr is `0x${string}` {
  return /^0x[0-9a-fA-F]{40}$/.test(addr)
}

async function callDepositAndLock() {
  if (!provider.connected || !store.contractAddress) return
  const acct = provider.account
  if (!acct) return
  store.status = 'Sending depositAndLock...'
  try {
    const txHash = await writeContract(config, {
      abi: ABI,
      address: store.contractAddress as `0x${string}`,
      functionName: 'depositAndLock',
      args: [BigInt(amount.value || '0'), BigInt(expiry.value || '0')],
      account: acct as `0x${string}`,
    })
    store.status = 'Sent tx: ' + txHash
    pendingTxs.value.push(txHash)
  } catch (err: any) {
    console.warn('callDepositAndLock error', err)
    store.status = 'Error: ' + (err?.shortMessage || err?.message || String(err))
  }
}

async function callWithdrawExpiredTo() {
  if (!provider.connected || !store.contractAddress) return
  const acct = provider.account
  if (!acct) return
  if (!ensureAddress(toAddress.value)) {
    store.status = 'Error: invalid to address'
    return
  }
  store.status = 'Sending withdrawExpiredTo...'
  try {
    const txHash = await writeContract(config, {
      abi: ABI,
      address: store.contractAddress as `0x${string}`,
      functionName: 'withdrawExpiredTo',
      args: [toAddress.value],
      account: acct as `0x${string}`,
    })
    store.status = 'Sent tx: ' + txHash
    pendingTxs.value.push(txHash)
  } catch (err: any) {
    console.warn('callWithdrawExpiredTo error', err)
    store.status = 'Error: ' + (err?.shortMessage || err?.message || String(err))
  }
}

async function fetchContractData() {
  if (!store.contractAddress) return
  console.log('fetchContractData for', store.contractAddress)
  try {
    const ownerRes = await readContract(config, {
      abi: ABI,
      address: store.contractAddress as `0x${string}`,
      functionName: 'owner',
    })
    ownerAddress.value = String(ownerRes)
  } catch (err) {
    ownerAddress.value = null
  }

  try {
    // getVeBalanceStored is a view and cheaper than getVeBalanceCurrent
    const vb = await readContract(config, {
      abi: ABI,
      address: store.contractAddress as `0x${string}`,
      functionName: 'getVeBalanceStored',
    })
    // vb can be bigint
    veBalance.value = String(vb)
  } catch (err) {
    veBalance.value = null
  }
}

onMounted(() => {
  if (provider.connected) {
    // provider.account is a computed ref (Pinia store). For status readability just coerce.
    store.status = 'Connected: ' + (provider.account as any)
  }
  // initial load of contract data
  fetchContractData()
})
</script>

<template>
  <div class="p-4 border rounded">
    <h2 class="text-xl mb-2">Owner Panel</h2>
    <div class="mb-2 flex items-center gap-3">
      <span class="ml-2">{{ store.status }}</span>
    </div>

    <div class="mb-4">
      <label class="block mb-1">Contract Address</label>
      <input
        v-model="store.contractAddress"
        class="w-full p-2 border rounded"
        placeholder="0x..."
      />
    </div>

    <div class="mb-4">
      <h3 class="font-semibold">depositAndLock</h3>
      <label class="block">Amount (uint128)</label>
      <input v-model="amount" class="w-full p-2 border rounded mb-2" />
      <label class="block">New Expiry (uint128)</label>
      <input v-model="expiry" class="w-full p-2 border rounded mb-2" />
      <button @click="callDepositAndLock" class="px-3 py-1 bg-green-600 text-white rounded">
        Send depositAndLock
      </button>
    </div>

    <div class="mb-4">
      <h3 class="font-semibold">withdrawExpiredTo</h3>
      <label class="block">To address</label>
      <input v-model="toAddress" class="w-full p-2 border rounded mb-2" placeholder="0x..." />
      <button @click="callWithdrawExpiredTo" class="px-3 py-1 bg-red-600 text-white rounded">
        Send withdrawExpiredTo
      </button>
    </div>

    <div class="mb-4">
      <h3 class="font-semibold">Contract Info</h3>
      <div class="mb-2">
        Owner: <span class="font-mono">{{ ownerAddress ?? '—' }}</span>
      </div>
      <div class="mb-2">
        VE balance (stored): <span class="font-mono">{{ veBalance ?? '—' }}</span>
      </div>
      <div class="mb-2">
        Pending tx:
        <div class="mt-2">
          <TransactionList v-if="pendingTxs.length" :txs="pendingTxs" />
          <div v-else class="font-mono">none</div>
        </div>
      </div>
      <button @click="fetchContractData" class="px-2 py-1 bg-slate-200 rounded">Refresh</button>
    </div>

    <div class="mt-4 text-sm text-gray-600">
      Note: This panel is intended for the SharedVePendle owner. Ensure the connected wallet is the
      contract owner.
    </div>
  </div>
</template>

<style scoped>
.border {
  border: 1px solid #e5e7eb;
}
</style>
