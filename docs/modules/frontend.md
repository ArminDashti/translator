# Frontend module

**Directory:** `web/`

Vue 3 SPA with dark theme, Vue Router, and Tailwind CSS.

## Pages

- `/login` — authentication
- `/transform` — main operation UI with dynamic dropdowns
- `/history` — sortable table, row modal, delete
- `/instructions` — edit per-key AI prompts
- `/stats` — usage counts by period
- `/settings` — OpenRouter config and clear history

## Dev proxy

Vite proxies `/api` to `localhost:8080` during `npm run dev`.
