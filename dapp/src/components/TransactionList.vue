<script setup lang="ts">
import type { PropType } from 'vue'
import TransactionCard from './TransactionCard.vue'
import type { Hash } from 'viem'

const props = defineProps({
  txs: { type: Array as PropType<Hash[]>, required: true },
})
</script>

<template>
  <div class="space-y-2">
    <TransactionCard v-for="tx in props.txs" :key="tx" :txHash="tx" />
  </div>
</template>
