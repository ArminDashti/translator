const TOKEN_KEY = 'translator_token'
const USERNAME_KEY = 'translator_username'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setAuth(token: string, username: string) {
  localStorage.setItem(TOKEN_KEY, token)
  localStorage.setItem(USERNAME_KEY, username)
}

export function clearAuth() {
  localStorage.removeItem(TOKEN_KEY)
  localStorage.removeItem(USERNAME_KEY)
}

export function getUsername(): string | null {
  return localStorage.getItem(USERNAME_KEY)
}

export function isAuthenticated(): boolean {
  return !!getToken()
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> | undefined),
  }

  const token = getToken()
  if (token) {
    headers.Authorization = `Bearer ${token}`
  }

  const res = await fetch(`/api/v1${path}`, { ...options, headers })

  if (res.status === 401) {
    clearAuth()
    window.location.href = '/login'
    throw new Error('Unauthorized')
  }

  if (!res.ok) {
    const body = await res.json().catch(() => ({ error: res.statusText }))
    throw new Error(body.error || 'Request failed')
  }

  if (res.status === 204) {
    return undefined as T
  }

  return res.json()
}

export const api = {
  login: (username: string, password: string) =>
    request<{ token: string; username: string }>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    }),

  transform: (payload: Record<string, unknown>) =>
    request<TransformResult>('/transform', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  getHistory: (params: { sort_by?: string; sort_order?: string }) => {
    const q = new URLSearchParams()
    if (params.sort_by) q.set('sort_by', params.sort_by)
    if (params.sort_order) q.set('sort_order', params.sort_order)
    return request<HistoryRecord[]>(`/history?${q}`)
  },

  getHistoryItem: (id: string) => request<HistoryRecord>(`/history/${id}`),

  deleteHistory: (id: string) =>
    request<void>(`/history/${id}`, { method: 'DELETE' }),

  getStats: () => request<StatsResponse>('/stats'),

  getInstructions: () => request<Instruction[]>('/instructions'),

  getInstruction: (key: string) => request<Instruction>(`/instructions/${key}`),

  updateInstruction: (key: string, content: string) =>
    request<Instruction>(`/instructions/${key}`, {
      method: 'PUT',
      body: JSON.stringify({ content }),
    }),

  getSettings: () => request<AppSettings>('/settings'),

  updateSettings: (payload: Partial<AppSettings>) =>
    request<AppSettings>('/settings', {
      method: 'PATCH',
      body: JSON.stringify(payload),
    }),

  clearData: () => request<void>('/settings/data', { method: 'DELETE' }),
}

export interface TransformResult {
  id: string
  type: string
  type_display: string
  input_text: string
  result_text: string
  model: string
  instruction_key: string
  formatted_date: string
}

export interface HistoryRecord {
  id: string
  type: string
  type_display: string
  input_text: string
  result_text: string
  model: string
  instruction_key: string
  metadata?: Record<string, string>
  formatted_date: string
}

export interface StatsBucket {
  simplify: number
  en_fa: number
  fa_en: number
  term: number
  refine: number
  symptoms: number
  total: number
}

export interface StatsResponse {
  today: StatsBucket
  yesterday: StatsBucket
  week: StatsBucket
  month: StatsBucket
  all_time: StatsBucket
}

export interface Instruction {
  key: string
  content: string
  updated_at: string
}

export interface AppSettings {
  openrouter_api_key: string
  model_name: string
  updated_at: string
}
