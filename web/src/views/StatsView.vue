<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, type StatsResponse } from '../api/client'

const stats = ref<StatsResponse | null>(null)
const loading = ref(true)
const error = ref('')

const periods = [
  { key: 'today' as const, label: 'Today' },
  { key: 'yesterday' as const, label: 'Yesterday' },
  { key: 'week' as const, label: 'Week' },
  { key: 'month' as const, label: 'Month' },
  { key: 'all_time' as const, label: 'All time' },
]

const categories = [
  { key: 'simplify' as const, label: 'Simplify' },
  { key: 'en_fa' as const, label: 'EN-FA' },
  { key: 'fa_en' as const, label: 'FA-EN' },
  { key: 'term' as const, label: 'Term' },
  { key: 'refine' as const, label: 'Refine' },
  { key: 'symptoms' as const, label: 'Symptoms' },
]

onMounted(async () => {
  try {
    stats.value = await api.getStats()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Failed to load stats'
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-xl font-semibold text-white">Stats</h2>
      <p class="text-sm text-gray-400">Request counts by operation type</p>
    </div>

    <div v-if="loading" class="text-gray-500">Loading...</div>
    <div v-else-if="error" class="text-red-400">{{ error }}</div>

    <div v-else-if="stats" class="card overflow-x-auto p-0">
      <table class="w-full text-left text-sm">
        <thead class="border-b border-surface-border bg-surface text-gray-400">
          <tr>
            <th class="px-4 py-3">Period</th>
            <th v-for="cat in categories" :key="cat.key" class="px-4 py-3">{{ cat.label }}</th>
            <th class="px-4 py-3 font-semibold">Total</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="period in periods"
            :key="period.key"
            class="border-b border-surface-border"
          >
            <td class="px-4 py-3 font-medium text-white">{{ period.label }}</td>
            <td v-for="cat in categories" :key="cat.key" class="px-4 py-3 text-gray-300">
              {{ stats[period.key][cat.key] }}
            </td>
            <td class="px-4 py-3 font-semibold text-accent">{{ stats[period.key].total }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
