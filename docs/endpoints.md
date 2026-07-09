# API Endpoints

All authenticated routes require `Authorization: Bearer <jwt>`.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/health` | No | Health check |
| POST | `/api/v1/auth/login` | No | Login with username/password, returns JWT |
| POST | `/api/v1/transform` | Yes | Run a transform operation |
| GET | `/api/v1/history` | Yes | List history (`sort_by`, `sort_order`, `limit`, `offset`) |
| GET | `/api/v1/history/:id` | Yes | Get single history record |
| DELETE | `/api/v1/history/:id` | Yes | Delete history record |
| GET | `/api/v1/stats` | Yes | Request counts by period and type |
| GET | `/api/v1/instructions` | Yes | List all instruction keys |
| GET | `/api/v1/instructions/:key` | Yes | Get instruction content |
| PUT | `/api/v1/instructions/:key` | Yes | Update instruction content |
| GET | `/api/v1/settings` | Yes | Get OpenRouter token and model |
| PATCH | `/api/v1/settings` | Yes | Update OpenRouter token and/or model |
| DELETE | `/api/v1/settings/data` | Yes | Delete all history rows |

## Transform request body

```json
{
  "operation": "translate|simplify|term|refine|symptoms",
  "text": "...",
  "direction": "en-fa|fa-en",
  "mode": "general|movie|formal|scientific|music",
  "movie_name": "...",
  "language": "en|fa",
  "style": "everyday|formal|slang"
}
```

Only include fields relevant to the selected operation.
