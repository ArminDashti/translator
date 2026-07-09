# Translator

AI-powered English ↔ Persian language tool with simplify, translate, term lookup, refine, and symptoms operations.

## Stack

- **Backend:** Go (Gin), PostgreSQL, OpenRouter
- **Frontend:** Vue 3, TypeScript, Tailwind CSS (dark theme only)

## Features

- Login with username/password (single user)
- Transform page with operation-specific dropdowns
- Editable AI instructions per operation mode
- History table with sorting, truncation, detail modal, and delete
- Stats by operation type (today, yesterday, week, month, all time)
- Settings for OpenRouter token, model, and clearing history

## Prerequisites

- Go 1.22+
- Node.js 18+
- Docker (PostgreSQL)

## Setup

1. Copy environment file:

```bash
cp .env.example .env
```

2. Edit `.env` — set `JWT_SECRET` to a long random string.

3. Start PostgreSQL:

```bash
docker compose up -d
```

4. Build the frontend:

```bash
cd web && npm install && npm run build && cd ..
```

5. Run the server:

```bash
go run ./cmd/server
```

Open [http://localhost:8080](http://localhost:8080).

### Development (hot reload UI)

```bash
# Terminal 1 — API
go run ./cmd/server

# Terminal 2 — Vite dev server (proxies /api to :8080)
cd web && npm run dev
```

Open [http://localhost:5173](http://localhost:5173).

## Default login

| Field    | Value            |
|----------|------------------|
| Username | `armin`          |
| Password | `Translator@2024` |

Override via `DEFAULT_USERNAME` and `DEFAULT_PASSWORD` in `.env` (only used on first boot when no users exist).

## Configuration

| Variable | Description |
|----------|-------------|
| `PORT` | HTTP port (default `8080`) |
| `JWT_SECRET` | Secret for signing login tokens |
| `DATABASE_URL` | PostgreSQL connection string |
| `STATIC_DIR` | Built frontend path (default `./web/dist`) |
| `DEFAULT_USERNAME` | Initial admin username |
| `DEFAULT_PASSWORD` | Initial admin password |

OpenRouter API key and model are configured in the **Settings** page (stored in the database).

## API overview

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/health` | No | Health check |
| POST | `/api/v1/auth/login` | No | Login |
| POST | `/api/v1/transform` | JWT | Run operation |
| GET | `/api/v1/history` | JWT | List history |
| GET | `/api/v1/history/:id` | JWT | Get history item |
| DELETE | `/api/v1/history/:id` | JWT | Delete history item |
| GET | `/api/v1/stats` | JWT | Usage statistics |
| GET | `/api/v1/instructions` | JWT | List instructions |
| GET | `/api/v1/instructions/:key` | JWT | Get instruction |
| PUT | `/api/v1/instructions/:key` | JWT | Update instruction |
| GET | `/api/v1/settings` | JWT | Get settings |
| PATCH | `/api/v1/settings` | JWT | Update settings |
| DELETE | `/api/v1/settings/data` | JWT | Clear all history |

## Project structure

```
cmd/server/           API entry point
internal/config/      Environment configuration
internal/db/          Database pool and migrations
internal/domain/      Entities and DTOs
internal/handler/     HTTP handlers
internal/middleware/  JWT auth middleware
internal/repository/  Data access
internal/service/     Business logic
migrations/           SQL migrations
web/                  Vue + Tailwind frontend
```
