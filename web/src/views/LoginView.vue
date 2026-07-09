<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { api, setAuth } from '../api/client'

const router = useRouter()
const username = ref('armin')
const password = ref('')
const error = ref('')
const loading = ref(false)

async function submit() {
  error.value = ''
  loading.value = true
  try {
    const res = await api.login(username.value, password.value)
    setAuth(res.token, res.username)
    router.push('/transform')
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Login failed'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-surface px-4">
    <div class="card w-full max-w-md">
      <h1 class="mb-2 text-2xl font-semibold text-white">Translator</h1>
      <p class="mb-6 text-sm text-gray-400">Sign in to continue</p>

      <form class="space-y-4" @submit.prevent="submit">
        <div>
          <label class="mb-1 block text-sm text-gray-400">Username</label>
          <input v-model="username" class="input-field" autocomplete="username" />
        </div>
        <div>
          <label class="mb-1 block text-sm text-gray-400">Password</label>
          <input
            v-model="password"
            type="password"
            class="input-field"
            autocomplete="current-password"
          />
        </div>
        <p v-if="error" class="text-sm text-red-400">{{ error }}</p>
        <button type="submit" class="btn-primary w-full" :disabled="loading">
          {{ loading ? 'Signing in...' : 'Sign in' }}
        </button>
      </form>
    </div>
  </div>
</template>
