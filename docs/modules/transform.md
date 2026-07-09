# Transform module

**Package:** `internal/service/transform.go` + `internal/handler/transform.go`

Maps UI operation selections to instruction keys, calls OpenRouter, and saves history.

## Operation → instruction key mapping

| Operation | Params | History type |
|-----------|--------|--------------|
| translate | en-fa + mode | EN-FA |
| translate | fa-en + mode | FA-EN |
| simplify | — | Simplify |
| term | en/fa + style | Term EN / Term FA |
| refine | style | Refine |
| symptoms | — | Symptoms |

## Dependencies

- `SettingsService` for API key and model
- `InstructionService` for system prompts
- `OpenRouterClient` for LLM calls
- `HistoryRepository` for persistence
