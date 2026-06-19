# Translator API

Gin (Go) backend for English ↔ Persian translation, proofreading, and lexical retrieval via OpenRouter.

## Features

- Four translation operations: English → Persian, English proofreading, Persian → English, English lexical retrieval
- OpenRouter LLM integration with three candidates per request
- User-managed settings (LLM models, default model)
- Layered instructions (fixed + user) editable via API
- Translation history with optional candidate selection
- Reviews with joined translation data
- Static Bearer token authentication

## Prerequisites

- Go 1.22+
- Docker (for PostgreSQL)
- OpenRouter API key

## Setup

1. Copy environment file:

```bash
cp .env.example .env
```

2. Edit `.env` with your `API_TOKEN` and `OPENROUTER_API_KEY`.

3. Start PostgreSQL:

```bash
docker compose up -d
```

4. Run the server:

```bash
go run ./cmd/server
```

Migrations run automatically on startup.

## Configuration

| Variable | Description |
|----------|-------------|
| `PORT` | HTTP port (default `8080`) |
| `API_TOKEN` | Static Bearer token for API auth |
| `DATABASE_URL` | PostgreSQL connection string |
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `INSTRUCTIONS_DIR` | Path to instruction markdown files (default `./instructions`) |

Models and default model are configured via the `/settings` API, not environment variables.

## API Overview

All endpoints except `/health` require:

```
Authorization: Bearer <API_TOKEN>
```

### Fresh install flow

```bash
# 1. Create a model
curl -X POST http://localhost:8080/api/v1/settings/models \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug":"claude-3.5-sonnet","openrouter_id":"anthropic/claude-3.5-sonnet","display_name":"Claude 3.5 Sonnet"}'

# 2. Set default model
curl -X PATCH http://localhost:8080/api/v1/settings \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"default_model_id":"<model-uuid>"}'

# 3. List operations
curl http://localhost:8080/api/v1/operations \
  -H "Authorization: Bearer $API_TOKEN"

# 4. Translate
curl -X POST http://localhost:8080/api/v1/translate \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation_id":"<operation-uuid>","text":"Hello world"}'
```

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/health` | Health check |
| GET | `/api/v1/operations` | List translation operations |
| POST | `/api/v1/translate` | Run translation operation |
| GET | `/api/v1/translations` | List translation history |
| GET | `/api/v1/translations/{id}` | Get translation |
| PATCH | `/api/v1/translations/{id}` | Select preferred candidate (1–3) |
| GET | `/api/v1/instructions/{operation_id}` | Get instruction layers |
| PUT | `/api/v1/instructions/{operation_id}` | Update instruction layer |
| GET | `/api/v1/settings` | Get app settings |
| PATCH | `/api/v1/settings` | Update app settings |
| GET | `/api/v1/settings/models` | List LLM models |
| POST | `/api/v1/settings/models` | Create LLM model |
| PUT | `/api/v1/settings/models/{id}` | Update LLM model |
| DELETE | `/api/v1/settings/models/{id}` | Delete LLM model |
| POST | `/api/v1/reviews` | Submit review |
| GET | `/api/v1/reviews` | List reviews with translation data |
| GET | `/api/v1/reviews/{id}` | Get review with translation data |

### Translate response

```json
{
  "id": "...",
  "operation_id": "...",
  "operation_slug": "en_to_fa",
  "model_id": "...",
  "candidate1": "...",
  "candidate2": "...",
  "candidate3": "...",
  "selected_candidate": null
}
```

### Update instructions

```json
{
  "layer": "fixed",
  "content": "# Your instruction markdown..."
}
```

`layer` must be `"fixed"` or `"user"`.

## Project structure

```
cmd/server/          Entry point
internal/config/     Environment configuration
internal/db/         Database pool and migrations
internal/domain/     Entities and DTOs
internal/handler/    HTTP handlers
internal/middleware/ Auth middleware
internal/repository/ Data access
internal/service/    Business logic
instructions/        Fixed and user instruction markdown files
migrations/          SQL migrations
```
