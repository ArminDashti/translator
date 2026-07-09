import { createRouter, createWebHistory } from 'vue-router'
import { isAuthenticated } from '../api/client'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/LoginView.vue'),
      meta: { public: true },
    },
    {
      path: '/',
      component: () => import('../components/AppLayout.vue'),
      children: [
        { path: '', redirect: '/transform' },
        {
          path: 'transform',
          name: 'transform',
          component: () => import('../views/TransformView.vue'),
        },
        {
          path: 'history',
          name: 'history',
          component: () => import('../views/HistoryView.vue'),
        },
        {
          path: 'instructions',
          name: 'instructions',
          component: () => import('../views/InstructionsView.vue'),
        },
        {
          path: 'stats',
          name: 'stats',
          component: () => import('../views/StatsView.vue'),
        },
        {
          path: 'settings',
          name: 'settings',
          component: () => import('../views/SettingsView.vue'),
        },
      ],
    },
  ],
})

router.beforeEach((to) => {
  if (!to.meta.public && !isAuthenticated()) {
    return { name: 'login' }
  }
  if (to.name === 'login' && isAuthenticated()) {
    return { name: 'transform' }
  }
})

export default router
