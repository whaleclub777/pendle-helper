<script setup lang="ts">
import { useProvider } from '../lib/provider'
import { useState } from '../lib/state'
import { computed, nextTick, onMounted, ref, watch } from 'vue'

const provider = useProvider()
const store = useState()

const selectedChainId = ref(provider.chainId ?? provider.defaultChainId)

const shortAccount = computed(() =>
  provider.account ? provider.account.slice(0, 6) + '…' + provider.account.slice(-4) : '—',
)
const shortContract = computed(() =>
  store.contractAddress
    ? store.contractAddress.slice(0, 6) + '…' + store.contractAddress.slice(-4)
    : '—',
)

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

const chainConfigs = [
  { id: 31337, name: 'Local', color: 'accent-sky-400' },
  { id: 1, name: 'Mainnet', color: 'accent-rose-400' },
]

watch(() => [provider.chainId, provider.defaultChainId, selectedChainId.value], () => {
  nextTick(() => {
    selectedChainId.value = provider.chainId ?? provider.defaultChainId
  })
})

async function selectChain(chainId: number) {
  try {
    await provider.connect(chainId)
  } catch (err: any) {
    console.warn('chain select failed', err)
  }
}
</script>

<template>
  <div
    class="flex flex-wrap gap-4 text-sm py-2 px-3 bg-gray-900 text-gray-100 text-size-xs rounded items-center"
  >
    <div class="flex items-center gap-2">
      <strong>Chain:</strong>
      <label class="flex items-center gap-1 select-none" v-for="cfg in chainConfigs" :key="cfg.id">
        <input
          type="radio"
          name="chain"
          :value="cfg.id"
          v-model="selectedChainId"
          @change.prevent="selectChain(cfg.id)"
          :class="cfg.color"
        />
        <span class="text-[0.7rem]" :for="cfg.id">{{ cfg.name }} ({{ cfg.id }})</span>
      </label>
    </div>
    <div><strong>RPC:</strong> {{ provider.rpcUrl }}</div>
    <div>
      <strong>Account:</strong> <span :title="provider.account || ''">{{ shortAccount }}</span>
    </div>
    <div>
      <strong>Contract:</strong>
      <span :title="store.contractAddress">
        <label class="cursor-pointer">
          <input type="file" class="hidden" accept="application/json" @change="onRunLatestFile" />
          {{ shortContract }}
        </label>
      </span>
    </div>
    <div>
      <strong>Status:</strong>
      <span>
        <input
          type="button"
          readonly
          @click="provider.connect()"
          :value="provider.status"
          :disabled="provider.connected"
          :class="provider.connected ? 'opacity-50' : 'cursor-pointer'"
        />
      </span>
    </div>
  </div>
</template>
