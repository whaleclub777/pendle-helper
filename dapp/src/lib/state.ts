import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useState = defineStore('state', () => {
  const contractAddress = ref('')
  const status = ref('')

  const parseContractAddress = (input: object, contractName: string) => {
    let addr: string | undefined
    const data = input as any
    if (data?.returns?.svp?.value) addr = data.returns.svp.value
    if (!addr && Array.isArray(data?.transactions)) {
      const tx = data.transactions.find((t: any) => t.contractName === contractName)
      if (tx?.contractAddress) addr = tx.contractAddress
    }
    return addr
  }

  // Try to auto-load the deploy broadcast's run-latest.json to pre-fill the contract address
  async function loadRunLatestAuto() {
    try {
      // Prefer the copied broadcast.json inside the dapp assets (written by vite plugin)
      // path relative to this file: dapp/src/lib -> ../../assets/broadcast.json
      // eslint-disable-next-line @typescript-eslint/ban-ts-comment
      // @ts-ignore -- allow JSON import
      const mod = await import('../../assets/broadcast.json')
      const data = mod?.default ?? mod
      const addr = parseContractAddress(data, 'SharedVePendle')
      if (addr) {
        contractAddress.value = addr
        status.value = 'Loaded contract address from run-latest.json: ' + addr
      } else {
        status.value = 'run-latest.json found but could not locate SharedVePendle address'
      }
    } catch (err: any) {
      status.value = 'Auto-load failed: ' + (err?.message || String(err))
    }
  }

  // Parse a user-selected run-latest.json File and extract SharedVePendle address
  async function onRunLatestFile(file: File) {
    if (!file) return
    try {
      const text = await file.text()
      const data = JSON.parse(text)
      const addr = parseContractAddress(data, 'SharedVePendle')
      if (addr) {
        contractAddress.value = addr
        status.value = 'Loaded contract address from selected file: ' + addr
      } else {
        status.value = 'Selected file parsed but no SharedVePendle address found'
      }
    } catch (err: any) {
      status.value = 'Failed to parse file: ' + (err?.message || String(err))
    }
  }

  return {
    contractAddress,
    status,
    loadRunLatestAuto,
    onRunLatestFile,
  }
})
