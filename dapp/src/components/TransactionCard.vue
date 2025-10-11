<script setup lang="ts">
import { computed } from 'vue'
import { useWaitForTransactionReceipt } from '@wagmi/vue'
import type { Hash } from 'viem'
import { formatTime } from '@/lib/utils';

const props = defineProps<{
  txHash: Hash
  label?: string
}>()

// watch the transaction receipt
const result = useWaitForTransactionReceipt({ hash: props.txHash, confirmations: 0 })
console.log(result)

const status = computed(() => result.status.value)

const shortHash = computed(() => {
  if (!props.txHash) return '—'
  return `${props.txHash.slice(0, 10)}...${props.txHash.slice(-6)}`
})

const blockNumber = computed(() => result.data.value?.blockNumber ?? null)
const gasUsed = computed(() => result.data.value?.gasUsed ?? null)

// Track when an error was last reported by the composable
const errorUpdatedAt = computed(() => result.errorUpdatedAt.value)
const dataUpdatedAt = computed(() => result.dataUpdatedAt.value)
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
      <div v-if="errorUpdatedAt">
        Error updated at:
        <span class="font-mono">{{ formatTime(errorUpdatedAt) }}</span>
      </div>
      <div v-if="errorUpdatedAt">
        Error message:
        <span class="font-mono">{{ result.error.value?.message ?? '—' }}</span>
      </div>
      <div>
        Block: <span class="font-mono">{{ blockNumber }}</span>
      </div>
      <div>
        Gas used: <span class="font-mono">{{ gasUsed }}</span>
      </div>
      <div v-if="dataUpdatedAt">
        Data updated at:
        <span class="font-mono">{{ formatTime(dataUpdatedAt) }}</span>
      </div>
    </div>
    <div v-else class="mt-2 text-xs text-slate-500">Awaiting confirmation...</div>
  </div>
</template>
