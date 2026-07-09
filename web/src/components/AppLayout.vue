<script setup lang="ts">
import { RouterLink, RouterView, useRoute } from 'vue-router'
import { clearAuth, getUsername } from '../api/client'

const route = useRoute()
const username = getUsername() || 'armin'

const links = [
  { to: '/transform', label: 'Transform' },
  { to: '/history', label: 'History' },
  { to: '/instructions', label: 'Instructions' },
  { to: '/stats', label: 'Stats' },
  { to: '/settings', label: 'Settings' },
]

function logout() {
  clearAuth()
  window.location.href = '/login'
}
</script>

<template>
  <div class="min-h-screen bg-surface">
    <header class="border-b border-surface-border bg-surface-raised">
      <div class="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
        <div class="flex items-center gap-8">
          <h1 class="text-lg font-semibold text-white">Translator</h1>
          <nav class="flex gap-1">
            <RouterLink
              v-for="link in links"
              :key="link.to"
              :to="link.to"
              class="rounded-lg px-3 py-2 text-sm transition"
              :class="
                route.path === link.to
                  ? 'bg-accent/20 text-accent'
                  : 'text-gray-400 hover:bg-surface-border/50 hover:text-white'
              "
            >
              {{ link.label }}
            </RouterLink>
          </nav>
        </div>
        <div class="flex items-center gap-4">
          <span class="text-sm text-gray-400">{{ username }}</span>
          <button class="btn-ghost text-sm" @click="logout">Logout</button>
        </div>
      </div>
    </header>
    <main class="mx-auto max-w-6xl px-4 py-8">
      <RouterView />
    </main>
  </div>
</template>
