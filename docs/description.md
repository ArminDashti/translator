# Translator

AI-powered English ↔ Persian language web app. Users log in, run transform operations (translate, simplify, term lookup, refine, symptoms) via OpenRouter, and manage history, instructions, stats, and settings through a dark-themed Vue UI.

## Tech stack

- Go 1.22 + Gin REST API
- PostgreSQL 16
- Vue 3 + TypeScript + Tailwind CSS
- OpenRouter for LLM calls
- Docker Compose for full-stack deployment

## Run

### Docker (full stack)

```powershell
.\run-on-docker.ps1
```

Web UI: http://localhost:8082 | API: http://localhost:8080

### Local development

1. `docker compose up -d postgres` (or use existing Postgres)
2. `cp .env.example .env` and set `JWT_SECRET`
3. `cd web && npm install && npm run build`
4. `go run ./cmd/server` → http://localhost:8080

Default login: `armin` / `Translator@2024`
