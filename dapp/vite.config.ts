import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import UnoCSS from '@unocss/vite'
import { promises as fs } from 'node:fs'
import path from 'node:path'

// Copy run-latest.json from the repo broadcast folder into dapp/assets/broadcast.json
async function copyRunLatestJson(): Promise<void> {
  try {
    const repoRoot = path.resolve(__dirname, '..')
    const src = path.join(repoRoot, 'broadcast', 'DeploySharedVePendle.s.sol', '31337', 'run-latest.json')
    const outDir = path.resolve(__dirname, 'assets')
    const dest = path.join(outDir, 'broadcast.json')

    // Read source if it exists
    const data = await fs.readFile(src, { encoding: 'utf8' })

    // Ensure output directory exists
    await fs.mkdir(outDir, { recursive: true })
    await fs.writeFile(dest, data, { encoding: 'utf8' })
  } catch (err: any) {
    // no-op: missing file is acceptable during CI or clean checkouts
    // but surface debug info during dev builds
    if (process.env.NODE_ENV !== 'production') {
      // eslint-disable-next-line no-console
      console.warn('copy-run-latest-json:', err?.message ?? err)
    }
  }
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    vueDevTools(),
    UnoCSS(),
    // Copy latest broadcast file into the dapp assets for easy import at runtime
    {
      name: 'copy-run-latest-json',
      async buildStart() {
        await copyRunLatestJson()
      }
    }
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    },
  },
})
