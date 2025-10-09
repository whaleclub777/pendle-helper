import { ref, computed, watch } from 'vue'

// DEBUG default from env or window.DEBUG; runtime toggle available via returned API
const initialDebug = import.meta.env.VITE_DEBUG === 'true' || (window as any).DEBUG === true

export function useProvider() {
  const DEBUG = ref<boolean>(initialDebug)
  const rpcUrl = ref<string>((import.meta.env.VITE_RPC_URL as string) || 'http://127.0.0.1:8545')

  const injectedProvider = (window as any).ethereum as any

  // simple JSON-RPC provider that mirrors the EIP-1193 request interface used by injected wallets
  function createRpcProvider(urlRef: { value: string }) {
    let id = 1
    return {
      async request(payload: { method: string; params?: any[] }) {
        const body = {
          jsonrpc: '2.0',
          id: id++,
          method: payload.method,
          params: payload.params ?? [],
        }
        const res = await fetch(urlRef.value, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        })
        const json = await res.json()
        if (json.error) throw new Error(json.error.message || JSON.stringify(json.error))
        return json.result
      },
    }
  }

  const rpcProvider = createRpcProvider(rpcUrl)

  const provider = computed(() => (DEBUG.value ? rpcProvider : injectedProvider))

  const account = ref<string | null>(null)
  const connected = ref<boolean>(false)

  async function connect() {
    try {
      if (DEBUG.value) {
        const raw: any = await provider.value.request({ method: 'eth_accounts' })
        const accs: string[] = Array.isArray(raw) ? raw.filter(Boolean) : []
        account.value = accs.length > 0 ? (accs[0] as string) : null
        connected.value = !!account.value
        return account.value
      } else {
        if (!provider.value) throw new Error('No injected provider')
        const raw: any = await provider.value.request({ method: 'eth_requestAccounts' })
        const accs: string[] = Array.isArray(raw) ? raw.filter(Boolean) : []
        account.value = accs.length > 0 ? (accs[0] as string) : null
        connected.value = !!account.value
        return account.value
      }
    } catch (e) {
      connected.value = false
      account.value = null
      throw e
    }
  }

  async function request(payload: { method: string; params?: any[] }) {
    if (!provider.value || typeof provider.value.request !== 'function') {
      throw new Error('No provider available')
    }
    return provider.value.request(payload)
  }

  function setDebug(v: boolean) {
    DEBUG.value = v
  }

  // when rpcUrl changes we don't need special handling because rpcProvider reads rpcUrl ref
  watch(rpcUrl, (n) => {
    // noop placeholder in case consumers want to react
  })

  return {
    DEBUG,
    setDebug,
    rpcUrl,
    provider,
    connect,
    request,
    account,
    connected,
  }
}
