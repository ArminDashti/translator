<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { api, type TransformResult } from '../api/client'

type Operation = 'translate' | 'simplify' | 'term' | 'refine' | 'symptoms'

const operation = ref<Operation>('translate')
const text = ref('')
const direction = ref('en-fa')
const mode = ref('general')
const movieName = ref('')
const language = ref('en')
const style = ref('everyday')

const loading = ref(false)
const error = ref('')
const result = ref<TransformResult | null>(null)

const operations = [
  { value: 'translate', label: 'Translate' },
  { value: 'simplify', label: 'Simplify' },
  { value: 'term', label: 'Term' },
  { value: 'refine', label: 'Refine' },
  { value: 'symptoms', label: 'Symptoms' },
]

const enFaModes = [
  { value: 'general', label: 'General' },
  { value: 'movie', label: 'Movie' },
  { value: 'formal', label: 'Formal' },
  { value: 'scientific', label: 'Scientific' },
  { value: 'music', label: 'Music' },
]

const faEnModes = [
  { value: 'general', label: 'General' },
  { value: 'formal', label: 'Formal' },
  { value: 'scientific', label: 'Scientific' },
]

const styleOptions = [
  { value: 'everyday', label: 'Everyday' },
  { value: 'formal', label: 'Formal' },
  { value: 'slang', label: 'Slang' },
]

const showMovieField = computed(
  () => operation.value === 'translate' && direction.value === 'en-fa' && mode.value === 'movie'
)

const translateModes = computed(() =>
  direction.value === 'en-fa' ? enFaModes : faEnModes
)

watch(direction, () => {
  const valid = translateModes.value.some((m) => m.value === mode.value)
  if (!valid) mode.value = 'general'
})

async function submit() {
  error.value = ''
  result.value = null
  loading.value = true

  const payload: Record<string, unknown> = {
    operation: operation.value,
    text: text.value,
  }

  if (operation.value === 'translate') {
    payload.direction = direction.value
    payload.mode = mode.value
    if (showMovieField.value) payload.movie_name = movieName.value
  } else if (operation.value === 'term') {
    payload.language = language.value
    payload.style = style.value
  } else if (operation.value === 'refine') {
    payload.style = style.value
  }

  try {
    result.value = await api.transform(payload)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Transform failed'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-xl font-semibold text-white">Transform</h2>
      <p class="text-sm text-gray-400">Run AI-powered language operations</p>
    </div>

    <div class="card space-y-4">
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="mb-1 block text-sm text-gray-400">Operation</label>
          <select v-model="operation" class="select-field">
            <option v-for="op in operations" :key="op.value" :value="op.value">
              {{ op.label }}
            </option>
          </select>
        </div>

        <template v-if="operation === 'translate'">
          <div>
            <label class="mb-1 block text-sm text-gray-400">Direction</label>
            <select v-model="direction" class="select-field">
              <option value="en-fa">EN → FA</option>
              <option value="fa-en">FA → EN</option>
            </select>
          </div>
          <div>
            <label class="mb-1 block text-sm text-gray-400">Mode</label>
            <select v-model="mode" class="select-field">
              <option v-for="m in translateModes" :key="m.value" :value="m.value">
                {{ m.label }}
              </option>
            </select>
          </div>
          <div v-if="showMovieField">
            <label class="mb-1 block text-sm text-gray-400">Movie name</label>
            <input v-model="movieName" class="input-field" placeholder="e.g. The Godfather" />
          </div>
        </template>

        <template v-if="operation === 'term'">
          <div>
            <label class="mb-1 block text-sm text-gray-400">Language</label>
            <select v-model="language" class="select-field">
              <option value="en">English prompt</option>
              <option value="fa">Persian prompt</option>
            </select>
          </div>
          <div>
            <label class="mb-1 block text-sm text-gray-400">Style</label>
            <select v-model="style" class="select-field">
              <option v-for="s in styleOptions" :key="s.value" :value="s.value">
                {{ s.label }}
              </option>
            </select>
          </div>
        </template>

        <template v-if="operation === 'refine'">
          <div>
            <label class="mb-1 block text-sm text-gray-400">Style</label>
            <select v-model="style" class="select-field">
              <option v-for="s in styleOptions" :key="s.value" :value="s.value">
                {{ s.label }}
              </option>
            </select>
          </div>
        </template>
      </div>

      <div>
        <label class="mb-1 block text-sm text-gray-400">Input text</label>
        <textarea
          v-model="text"
          rows="6"
          class="input-field resize-y"
          placeholder="Enter text to transform..."
        />
      </div>

      <p v-if="error" class="text-sm text-red-400">{{ error }}</p>

      <button class="btn-primary" :disabled="loading || !text.trim()" @click="submit">
        {{ loading ? 'Processing...' : 'Transform' }}
      </button>
    </div>

    <div v-if="result" class="card space-y-3">
      <div class="flex flex-wrap items-center gap-3 text-sm text-gray-400">
        <span class="rounded bg-accent/20 px-2 py-0.5 text-accent">{{ result.type_display }}</span>
        <span>{{ result.model }}</span>
        <span>{{ result.formatted_date }}</span>
      </div>
      <div>
        <h3 class="mb-1 text-sm font-medium text-gray-400">Result</h3>
        <p class="whitespace-pre-wrap rounded-lg border border-surface-border bg-surface p-4 text-gray-100">
          {{ result.result_text }}
        </p>
      </div>
    </div>
  </div>
</template>
