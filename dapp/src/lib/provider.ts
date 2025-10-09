import { computed } from 'vue'
import { useAccount, useConnect, useDisconnect } from '@wagmi/vue'
import { getPublicClient, getWalletClient } from 'wagmi/actions'

import { createConfig, http } from 'wagmi'
import { anvil, mainnet } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'

// Allow optional RPC override via env; fallback to local anvil & public mainnet
const localRpc = import.meta.env.VITE_RPC_URL || 'http://127.0.0.1:8545'

// We include both hardhat (31337) and mainnet so the injected wallet can switch.
export const config = createConfig({
  chains: [anvil, mainnet],
  connectors: [injected()],
  transports: {
    [anvil.id]: http(localRpc),
    [mainnet.id]: http(), // default public transport
  },
  ssr: false,
})

// New wagmi-based provider composable. Backwards compatibility with previous API is intentionally dropped.
export function useProvider() {
  const accountHook = useAccount()
  const { connectAsync, connectors, status: connectStatus, error: connectError } = useConnect()
  const { disconnectAsync } = useDisconnect()
  const publicClient = computed(() => getPublicClient(config))
  const walletClient = computed(() => {
    try {
      return getWalletClient(config)
    } catch {
      return undefined
    }
  })

  async function connect() {
    // choose first ready connector
    const connector = connectors.find((c: any) => c.ready) || connectors[0]
    if (!connector) throw new Error('No connector available')
    const res = await connectAsync({ connector })
    // res contains accounts array
    return (res as any).accounts?.[0]
  }

  async function disconnect() {
    try {
      await disconnectAsync()
    } catch {}
  }

  async function request<T = any>({ method, params }: { method: string; params?: any[] }) {
    // prefer wallet transport if connected; fallback to public client
    const wc: any = (walletClient as any).value
    const pc: any = publicClient.value
    const transport = wc?.transport || pc?.transport
    if (!transport || typeof (transport as any).request !== 'function') {
      throw new Error('No transport available')
    }
    return (transport as any).request({ method, params }) as Promise<T>
  }

  const account = computed(() => accountHook.address || null)
  const connected = computed(() => accountHook.isConnected)

  return {
    account,
    connected,
    connect,
    disconnect,
    request,
    publicClient,
    walletClient,
    connectStatus,
    connectError,
  }
}
