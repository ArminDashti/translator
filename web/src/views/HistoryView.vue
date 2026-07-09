<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, type HistoryRecord } from '../api/client'
import HistoryModal from '../components/HistoryModal.vue'

const items = ref<HistoryRecord[]>([])
const loading = ref(true)
const error = ref('')
const sortBy = ref('datetime')
const sortOrder = ref('desc')
const selected = ref<HistoryRecord | null>(null)

async function load() {
  loading.value = true
  error.value = ''
  try {
    items.value = await api.getHistory({
      sort_by: sortBy.value,
      sort_order: sortOrder.value,
    })
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Failed to load history'
  } finally {
    loading.value = false
  }
}

function toggleSort(column: string) {
  if (sortBy.value === column) {
    sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc'
  } else {
    sortBy.value = column
    sortOrder.value = column === 'datetime' ? 'desc' : 'asc'
  }
  load()
}

async function remove(id: string, event: Event) {
  event.stopPropagation()
  if (!confirm('Delete this history entry?')) return
  try {
    await api.deleteHistory(id)
    items.value = items.value.filter((i) => i.id !== id)
    if (selected.value?.id === id) selected.value = null
  } catch (e) {
    alert(e instanceof Error ? e.message : 'Delete failed')
  }
}

function sortIcon(column: string) {
  if (sortBy.value !== column) return '↕'
  return sortOrder.value === 'asc' ? '↑' : '↓'
}

onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-xl font-semibold text-white">History</h2>
      <p class="text-sm text-gray-400">Past transformations</p>
    </div>

    <div v-if="error" class="text-sm text-red-400">{{ error }}</div>

    <div class="card overflow-hidden p-0">
      <div class="overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="border-b border-surface-border bg-surface text-gray-400">
            <tr>
              <th class="cursor-pointer px-4 py-3 hover:text-white" @click="toggleSort('type')">
                Type {{ sortIcon('type') }}
              </th>
              <th class="px-4 py-3">Input</th>
              <th class="px-4 py-3">Result</th>
              <th class="cursor-pointer px-4 py-3 hover:text-white" @click="toggleSort('model')">
                Model {{ sortIcon('model') }}
              </th>
              <th class="cursor-pointer px-4 py-3 hover:text-white" @click="toggleSort('datetime')">
                DateTime {{ sortIcon('datetime') }}
              </th>
              <th class="px-4 py-3"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="6" class="px-4 py-8 text-center text-gray-500">Loading...</td>
            </tr>
            <tr v-else-if="items.length === 0">
              <td colspan="6" class="px-4 py-8 text-center text-gray-500">No history yet</td>
            </tr>
            <tr
              v-for="item in items"
              :key="item.id"
              class="cursor-pointer border-b border-surface-border transition hover:bg-surface"
              @click="selected = item"
            >
              <td class="px-4 py-3">
                <span class="table-cell-truncate block">{{ item.type_display }}</span>
              </td>
              <td class="px-4 py-3">
                <span class="table-cell-truncate block" :title="item.input_text">{{ item.input_text }}</span>
              </td>
              <td class="px-4 py-3">
                <span class="table-cell-truncate block" :title="item.result_text">{{ item.result_text }}</span>
              </td>
              <td class="px-4 py-3">
                <span class="table-cell-truncate block">{{ item.model }}</span>
              </td>
              <td class="px-4 py-3 whitespace-nowrap">{{ item.formatted_date }}</td>
              <td class="px-4 py-3">
                <button
                  class="text-red-400 hover:text-red-300"
                  title="Delete"
                  @click="remove(item.id, $event)"
                >
                  ✕
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <HistoryModal v-if="selected" :item="selected" @close="selected = null" />
  </div>
</template>
