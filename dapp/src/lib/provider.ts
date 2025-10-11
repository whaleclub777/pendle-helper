import { computed, ref } from 'vue'
import { createConnector, useAccount } from '@wagmi/vue'

import { createConfig, http } from 'wagmi'
import { anvil, mainnet } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'
import { defineStore } from 'pinia'
import { createPublicClient, type Address } from 'viem'
import { extractRpcUrls } from '@wagmi/core'

// Allow optional RPC override via env; fallback to local anvil & public mainnet
const localRpc = (import.meta.env.VITE_RPC_URL as string) || 'http://127.0.0.1:8545'

export const localDevConnector = createConnector<ReturnType<typeof createPublicClient>>(
  (config) => {
    const transports = config.transports
    const rpcUrlMap = new Map<number, string>()
    config.chains.forEach((chain) => {
      const rpcUrl = extractRpcUrls({ transports, chain })?.[0] as string
      rpcUrlMap.set(chain.id, rpcUrl)
    })
    const rpcUrl = rpcUrlMap.get(anvil.id) ?? localRpc
    let provider: ReturnType<typeof createPublicClient> | undefined

    return {
      id: 'dev',
      name: 'Local Dev RPC',
      type: 'local',
      async connect({ chainId, withCapabilities } = {}) {
        const currentChainId = await this.getChainId()
        const accounts = await this.getAccounts()
        return {
          accounts: (withCapabilities
            ? accounts.map((address) => ({ address, capabilities: {} }))
            : accounts) as never,
          chainId: currentChainId,
        }
      },
      async disconnect() {
        provider = undefined
      },
      async getAccounts() {
        const p = await this.getProvider()
        return (await p.request({ method: 'eth_accounts', params: undefined })) as Address[]
      },
      async getChainId() {
        const p = await this.getProvider()
        return await p.getChainId()
      },
      async isAuthorized() {
        return true
      },
      async getProvider() {
        if (!provider) {
          provider = createPublicClient({
            chain: anvil,
            transport: http(rpcUrl),
          })
        }
        return provider
      },
      onAccountsChanged() {},
      onChainChanged() {},
      onDisconnect() {
        provider = undefined
      },
    }
  },
)

// We include both hardhat (31337) and mainnet so the injected wallet can switch.
export const config = createConfig({
  chains: [anvil, mainnet],
  connectors: [injected(), localDevConnector],
  transports: {
    [anvil.id]: http(localRpc),
    [mainnet.id]: http(), // default public transport
  },
  ssr: false,
})

// New wagmi-based provider composable. Backwards compatibility with previous API is intentionally dropped.
export const useProvider = defineStore('provider', () => {
  const accountHook = useAccount({
    config,
  })
  const defaultChainId = ref(anvil.id)
  const rpcUrl = computed(() => {
    if (!accountHook.chain.value) return '—'
    const url = extractRpcUrls({
      transports: config._internal.transports,
      chain: accountHook.chain.value,
    })[0]
    return url ?? '—'
  })
  const connect = async (chainId?: number) => {
    chainId = chainId ?? defaultChainId.value
    try {
      const result = await accountHook.connector.value?.connect({
        chainId,
      })
      return result?.accounts
    } catch (e) {
      console.error('connect error', e)
    }
  }

  const request = async (args: { method: string; params?: any[] }) => {
    const p = await accountHook.connector.value?.getProvider()
    console.warn('requesting', p)
    return (p as any)?.request(args as any)
  }
  const selectedAccount = ref<Address | null>()
  const selectAccount = (addr: Address | null) => {
    selectedAccount.value = addr
  }
  const account = computed(() => selectedAccount.value ?? accountHook.address.value)
  return {
    defaultChainId,
    request,
    connect,
    connector: accountHook.connector,
    chainId: accountHook.chainId,
    rpcUrl,
    selectedAccount,
    selectAccount,
    accounts: accountHook.addresses,
    account,
    connected: accountHook.isConnected,
    status: accountHook.status,
  }
})
