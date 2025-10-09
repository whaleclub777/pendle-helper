import presetWind4 from '@unocss/preset-wind4'
import { defineConfig, presetAttributify } from 'unocss'

export default defineConfig({
  presets: [
    presetWind4(),
    presetAttributify(),
  ],
})
