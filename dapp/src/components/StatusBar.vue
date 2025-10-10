<script setup lang="ts">
import { useProvider } from '../lib/provider'
import { useState } from '../lib/state'
import { computed, onMounted } from 'vue'

const provider = useProvider()
const store = useState()

const shortAccount = computed(() => provider.account ? provider.account.slice(0, 6) + '…' + provider.account.slice(-4) : '—')
const shortContract = computed(() => store.contractAddress ? store.contractAddress.slice(0, 6) + '…' + store.contractAddress.slice(-4) : '—')

onMounted(() => {
  store.loadRunLatestAuto()
  provider.connect()
})
async function onRunLatestFile(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  await store.onRunLatestFile(file)
  // reset input so same file can be re-selected later
  if (input) input.value = ''
}
</script>

<template>
  <div class="flex flex-wrap gap-4 text-sm py-2 px-3 bg-gray-900 text-gray-100 text-size-xs rounded items-center">
    <div><strong>Chain:</strong> {{ provider.chainId || '—' }}</div>
    <div><strong>RPC:</strong> {{ provider.rpcUrl }}</div>
    <div><strong>Account:</strong> <span :title="provider.account || ''">{{ shortAccount }}</span></div>
    <div><strong>Contract:</strong> <span :title="store.contractAddress">
      <label class="cursor-pointer">
        <input
          type="file"
          class="hidden"
          accept="application/json"
          @change="onRunLatestFile"
        />
        {{ shortContract }}
      </label>

    </span></div>
    <div><strong>Status:</strong> <span>
      <input
        type="button"
        readonly
        @click="provider.connect()"
        :value="provider.status"
        :disabled="provider.connected"
        :class="provider.connected ? 'opacity-50' : 'cursor-pointer'"
      />
    </span></div>
  </div>
</template>
