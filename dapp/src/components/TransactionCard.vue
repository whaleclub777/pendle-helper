<script setup lang="ts">
import { computed } from 'vue'
import { useWaitForTransactionReceipt } from '@wagmi/vue'
import type { Hash } from 'viem'

const props = defineProps<{
  txHash: Hash
  label?: string
}>()

// watch the transaction receipt
const result = useWaitForTransactionReceipt({ hash: props.txHash, confirmations: 0 })
console.log(result)

const status = computed(() => {
  return result.status.value
})

const shortHash = computed(() => {
  if (!props.txHash) return '—'
  return `${props.txHash.slice(0, 10)}...${props.txHash.slice(-6)}`
})

const blockNumber = computed(() => result.data.value?.blockNumber ?? null)
const gasUsed = computed(() => result.data.value?.gasUsed ?? null)
</script>

<template>
  <div class="p-3 border rounded bg-white shadow-sm">
    <div class="flex justify-between items-start">
      <div>
        <div class="text-sm text-slate-600">{{ props.label ?? 'Transaction' }}</div>
        <div class="font-mono text-xs">{{ shortHash }}</div>
      </div>
      <div>
        <span
          :class="{
            'px-2 py-0.5 rounded text-xs font-medium': true,
            'bg-yellow-100 text-yellow-800': status === 'pending',
            'bg-green-100 text-green-800': status === 'success',
            'bg-red-100 text-red-800': status === 'error',
          }"
        >
          {{ status }}
        </span>
      </div>
    </div>

    <div v-if="result.data" class="mt-2 text-xs text-slate-700">
      <div>
        Block: <span class="font-mono">{{ blockNumber }}</span>
      </div>
      <div>
        Gas used: <span class="font-mono">{{ gasUsed }}</span>
      </div>
    </div>
    <div v-else class="mt-2 text-xs text-slate-500">Awaiting confirmation...</div>
  </div>
</template>

<style scoped>
.font-mono {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, 'Roboto Mono', 'Courier New', monospace;
}
</style>
