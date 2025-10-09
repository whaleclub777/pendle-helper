<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { encodeFunctionData } from 'viem'
import { useProvider } from '../composables/useProvider'

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

const {
  DEBUG,
  setDebug,
  rpcUrl,
  provider,
  connect: providerConnect,
  request: providerRequest,
  account: providerAccount,
  connected: providerConnected,
} = useProvider()

const connected = providerConnected
const account = providerAccount
const contractAddress = ref('')
const amount = ref<string>('0')
const expiry = ref<string>('0')
const toAddress = ref('')
const status = ref('')

async function connect() {
  try {
    try {
      const acc = await providerConnect()
      if (acc) {
        status.value = (DEBUG.value ? 'Connected (RPC): ' : 'Connected: ') + acc
      } else {
        status.value = DEBUG.value ? 'No accounts available from RPC ' + rpcUrl.value : 'No account returned'
      }
    } catch (err: any) {
      status.value = 'Connect failed: ' + (err?.message || String(err))
    }
  } catch (err: any) {
    status.value = 'Connect failed: ' + (err?.message || String(err))
  }
}

async function callDepositAndLock() {
  if (!connected.value || !contractAddress.value || !account.value) return
  status.value = 'Sending depositAndLock...'
  try {
    const data = encodeFunctionData({
      abi: ABI,
      functionName: 'depositAndLock',
      args: [BigInt(amount.value || '0'), BigInt(expiry.value || '0')],
    })
    const txHash = await providerRequest({
      method: 'eth_sendTransaction',
      params: [
        {
          from: account.value,
          to: contractAddress.value,
          data,
        },
      ],
    })
    status.value = 'Sent tx: ' + txHash
  } catch (err: any) {
    status.value = 'Error: ' + (err?.message || String(err))
  }
}

async function callWithdrawExpiredTo() {
  if (!connected.value || !contractAddress.value || !account.value) return
  status.value = 'Sending withdrawExpiredTo...'
  try {
    const data = encodeFunctionData({
      abi: ABI,
      functionName: 'withdrawExpiredTo',
      args: [toAddress.value as `0x${string}`],
    })
    const txHash = await providerRequest({
      method: 'eth_sendTransaction',
      params: [
        {
          from: account.value,
          to: contractAddress.value,
          data,
        },
      ],
    })
    status.value = 'Sent tx: ' + txHash
  } catch (err: any) {
    status.value = 'Error: ' + (err?.message || String(err))
  }
}

// Auto-connect when running in DEBUG mode so owner can use the dev RPC immediately
onMounted(() => {
  if (DEBUG.value) connect()
})
</script>

<template>
  <div class="p-4 border rounded">
    <h2 class="text-xl mb-2">Owner Panel</h2>
    <div class="mb-2 flex items-center gap-3">
      <div>
        <label class="mr-2">Mode:</label>
        <select v-model="DEBUG" @change="() => setDebug(DEBUG)" class="p-1 border rounded">
          <option :value="false">Wallet</option>
          <option :value="true">RPC (dev)</option>
        </select>
      </div>
      <button @click="connect" class="px-3 py-1 bg-blue-500 text-white rounded">Connect</button>
      <span class="ml-2">{{ status }}</span>
    </div>

    <div class="mb-4">
      <label class="block mb-1">Contract Address</label>
      <input v-model="contractAddress" class="w-full p-2 border rounded" placeholder="0x..." />
    </div>

    <div class="mb-4">
      <h3 class="font-semibold">depositAndLock</h3>
      <label class="block">Amount (uint128)</label>
      <input v-model="amount" class="w-full p-2 border rounded mb-2" />
      <label class="block">New Expiry (uint128)</label>
      <input v-model="expiry" class="w-full p-2 border rounded mb-2" />
      <button @click="callDepositAndLock" class="px-3 py-1 bg-green-600 text-white rounded">Send depositAndLock</button>
    </div>

    <div class="mb-4">
      <h3 class="font-semibold">withdrawExpiredTo</h3>
      <label class="block">To address</label>
      <input v-model="toAddress" class="w-full p-2 border rounded mb-2" placeholder="0x..." />
      <button @click="callWithdrawExpiredTo" class="px-3 py-1 bg-red-600 text-white rounded">Send withdrawExpiredTo</button>
    </div>

    <div class="mt-4 text-sm text-gray-600">Note: This panel is intended for the SharedVePendle owner. Ensure the connected wallet is the contract owner.</div>
  </div>
</template>

<style scoped>
.border { border: 1px solid #e5e7eb; }
</style>
