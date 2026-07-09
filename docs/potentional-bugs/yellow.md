# Potential bugs (minor)

**[Migration 002]** — Fixed: `default_model_id` FK is dropped before `llm_models`. Use `--delete-volume=yes` if a prior failed migration left the DB dirty.

**[CORS]** — API allows `localhost:5173` (Vite dev) and `localhost:8082` (Docker web). Add origins in `cmd/server/main.go` for other hostnames.

**[JWT]** — Tokens expire after 7 days with no refresh flow; user must re-login.

**[OpenRouter key]** — Stored in plaintext in PostgreSQL. Acceptable for single-user local use; encrypt at rest for shared deployments.
