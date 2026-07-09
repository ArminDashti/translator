<script setup lang="ts">
import type { HistoryRecord } from '../api/client'

defineProps<{ item: HistoryRecord }>()
defineEmits<{ close: [] }>()
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" @click.self="$emit('close')">
    <div class="card max-h-[90vh] w-full max-w-2xl overflow-y-auto">
      <div class="mb-4 flex items-start justify-between">
        <div>
          <h3 class="text-lg font-semibold text-white">History details</h3>
          <p class="text-sm text-gray-400">{{ item.formatted_date }}</p>
        </div>
        <button class="text-gray-400 hover:text-white" @click="$emit('close')">✕</button>
      </div>

      <dl class="space-y-4 text-sm">
        <div>
          <dt class="text-gray-500">Type</dt>
          <dd class="text-white">{{ item.type_display }}</dd>
        </div>
        <div>
          <dt class="text-gray-500">Model</dt>
          <dd class="text-white">{{ item.model }}</dd>
        </div>
        <div>
          <dt class="text-gray-500">Instruction</dt>
          <dd class="text-white">{{ item.instruction_key }}</dd>
        </div>
        <div>
          <dt class="text-gray-500">Input</dt>
          <dd class="whitespace-pre-wrap rounded-lg border border-surface-border bg-surface p-3 text-gray-100">
            {{ item.input_text }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500">Result</dt>
          <dd class="whitespace-pre-wrap rounded-lg border border-surface-border bg-surface p-3 text-gray-100">
            {{ item.result_text }}
          </dd>
        </div>
      </dl>
    </div>
  </div>
</template>
