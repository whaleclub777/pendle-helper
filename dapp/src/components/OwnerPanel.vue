<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { encodeFunctionData } from 'viem'
import { useProvider } from '../lib/provider'
import { useState } from '../lib/state'

// Simple ABI subset for the functions we need
const ABI = [
  {
    name: 'depositAndLock',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'amount', type: 'uint128' },
      { name: 'newExpiry', type: 'uint128' },
    ],
    outputs: [{ name: 'newVeBalance', type: 'uint128' }],
  },
  {
    name: 'withdrawExpiredTo',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'to', type: 'address' }],
    outputs: [{ name: 'amount', type: 'uint128' }],
  },
]

const provider = useProvider()
const store = useState()
const amount = ref<string>('0')
const expiry = ref<string>('0')
const toAddress = ref('')
// use store.contractAddress and store.status directly (Pinia unwraps values)

async function callDepositAndLock() {
  if (!provider.connected || !store.contractAddress || !provider.account) return
  store.status = 'Sending depositAndLock...'
  try {
    const data = encodeFunctionData({
      abi: ABI,
      functionName: 'depositAndLock',
      args: [BigInt(amount.value || '0'), BigInt(expiry.value || '0')],
    })
    const from = provider.selectedAccount ?? provider.account
    const txHash = await provider.request({
      method: 'eth_sendTransaction',
      params: [
        {
          from,
          to: store.contractAddress,
          data,
        },
      ],
    })
    store.status = 'Sent tx: ' + txHash
  } catch (err: any) {
    store.status = 'Error: ' + (err?.message || String(err))
  }
}

async function callWithdrawExpiredTo() {
  if (!provider.connected || !store.contractAddress || !provider.account) return
  store.status = 'Sending withdrawExpiredTo...'
  try {
    const data = encodeFunctionData({
      abi: ABI,
      functionName: 'withdrawExpiredTo',
      args: [toAddress.value as `0x${string}`],
    })
    const from = provider.selectedAccount ?? provider.account
    const txHash = await provider.request({
      method: 'eth_sendTransaction',
      params: [
        {
          from,
          to: store.contractAddress,
          data,
        },
      ],
    })
    store.status = 'Sent tx: ' + txHash
  } catch (err: any) {
    console.warn('callWithdrawExpiredTo error', err)
    store.status = 'Error: ' + (err?.message || String(err))
  }
}

// Auto-connect when running in DEBUG mode so owner can use the dev RPC immediately
onMounted(() => {
  // auto-connect if already authorized (e.g., browser wallet remembers session)
  if (provider.connected) {
    store.status = 'Connected: ' + provider.account
  }
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
