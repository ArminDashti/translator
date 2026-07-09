<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api } from '../api/client'

const apiKey = ref('')
const modelName = ref('')
const loading = ref(true)
const saving = ref(false)
const clearing = ref(false)
const error = ref('')
const saved = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const settings = await api.getSettings()
    apiKey.value = settings.openrouter_api_key
    modelName.value = settings.model_name
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Failed to load settings'
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  error.value = ''
  saved.value = false
  try {
    await api.updateSettings({
      openrouter_api_key: apiKey.value,
      model_name: modelName.value,
    })
    saved.value = true
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Save failed'
  } finally {
    saving.value = false
  }
}

async function clearAll() {
  if (!confirm('Delete ALL history records? This cannot be undone.')) return
  clearing.value = true
  error.value = ''
  try {
    await api.clearData()
    alert('All history records have been deleted.')
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Clear failed'
  } finally {
    clearing.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-xl font-semibold text-white">Settings</h2>
      <p class="text-sm text-gray-400">OpenRouter configuration and data management</p>
    </div>

    <div v-if="loading" class="text-gray-500">Loading...</div>

    <div v-else class="card max-w-xl space-y-4">
      <div>
        <label class="mb-1 block text-sm text-gray-400">OpenRouter API token</label>
        <input v-model="apiKey" type="password" class="input-field" placeholder="sk-or-..." />
      </div>
      <div>
        <label class="mb-1 block text-sm text-gray-400">Model</label>
        <input
          v-model="modelName"
          class="input-field"
          placeholder="e.g. anthropic/claude-3.5-sonnet"
        />
      </div>

      <div class="flex items-center gap-4">
        <button class="btn-primary" :disabled="saving" @click="save">
          {{ saving ? 'Saving...' : 'Save settings' }}
        </button>
        <span v-if="saved" class="text-sm text-green-400">Saved</span>
      </div>

      <p v-if="error" class="text-sm text-red-400">{{ error }}</p>
    </div>

    <div class="card max-w-xl border-red-900/50">
      <h3 class="mb-2 font-medium text-red-400">Danger zone</h3>
      <p class="mb-4 text-sm text-gray-400">
        Remove all rows from the history table. Instructions and settings are kept.
      </p>
      <button class="btn-danger" :disabled="clearing" @click="clearAll">
        {{ clearing ? 'Clearing...' : 'Clear all history' }}
      </button>
    </div>
  </div>
</template>
