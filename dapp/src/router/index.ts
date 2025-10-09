import { createRouter, createWebHistory } from 'vue-router'

const OwnerPanel = () => import('../components/OwnerPanel.vue')

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'home', component: () => import('../App.vue') },
    { path: '/owner', name: 'owner', component: OwnerPanel },
  ],
})

export default router
