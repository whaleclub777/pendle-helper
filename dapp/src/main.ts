import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { WagmiPlugin } from '@wagmi/vue'
import App from './App.vue'
import router from './lib/router'
// UnoCSS generated utilities
import 'virtual:uno.css'
import { VueQueryPlugin } from '@tanstack/vue-query'
import { config } from './lib/provider'

const app = createApp(App)

app.use(createPinia())
app.use(router)
app.use(WagmiPlugin, { config })
app.use(VueQueryPlugin)

app.mount('#app')
