# Docker deployment

Unified Docker files at the **repo root** run API, web UI, and PostgreSQL together.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build: `api` target (Go) and `web` target (Vue + nginx) |
| `docker-compose.yml` | `postgres` + `api` + `web` on external `translator-net` |
| `nginx.conf.template` | Proxies `/api/` from web container to API |
| `build-docker-image.ps1` | Build API and/or web Docker images locally |
| `run-on-docker.ps1` | Local or SSH deploy script |
| `.docker/stack.manifest.json` | Image tags, container names, ports |

## Services

| Service | Container | Host port | Notes |
|---------|-----------|-----------|-------|
| `postgres` | `translator-postgres` | — | Volume `postgres_data` |
| `api` | `translator` | 8080 | Runs migrations on startup |
| `web` | `translator-web` | 8082 | Serves static UI; proxies `/api/*` → `translator:8080` |

## `build-docker-image.ps1`

| Flag | Default | Description |
|------|---------|-------------|
| `--target` | `all` | `api`, `web`, or `all` |
| `--no-cache` | `no` | `yes` rebuilds without Docker cache |
| `--compose-file` | `docker-compose.yml` | Compose file in repo root |

Builds images via `docker compose build`. Image tags come from `.docker/stack.manifest.json` (defaults: `translator-api:latest`, `translator-web:latest`). Run the stack afterward with `run-on-docker.ps1`.

## `run-on-docker.ps1`

| Flag | Default | Description |
|------|---------|-------------|
| `--ssh-string` | — | SSH config alias (e.g. `myvps`); omit for local Docker |
| `--delete-volume` | `no` | `yes` removes volumes before recreate |
| `--network` | `translator-net` | Docker network name |
| `--api-host` | `translator` | API hostname for nginx proxy |
| `--api-port` | `8080` | API port for nginx proxy |

**Local:** ensures `translator-net`, then `docker compose down` and `docker compose up -d --build`.

**Remote:** builds images locally, `docker save` both tags, transfers tarball + deploy files to `/opt/docker/translator`, loads images, ensures the network, runs compose without remote build. Pass only the SSH config alias (e.g. `--ssh-string=myvps`), not a full `ssh` command.

Set `JWT_SECRET` in the environment before running if you need a non-default secret (compose default is for local dev only).

**Default login:** `armin` / `Translator@2024` (from compose env).

**CORS:** The API must allow the web UI origin (`http://localhost:8082`) for browser login through nginx; Vite dev uses `http://localhost:5173`.
