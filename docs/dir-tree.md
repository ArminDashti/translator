```
translator/
├── .docker/
│   └── stack.manifest.json         # Docker image tags, ports, stack name
├── cmd/server/main.go              # Gin server entry, routes, static files
├── internal/
│   ├── config/config.go            # Env-based configuration
│   ├── db/db.go                    # Postgres pool and migrations
│   ├── domain/models.go            # Domain types and instruction keys
│   ├── handler/                    # HTTP handlers (auth, transform, history, etc.)
│   ├── middleware/auth.go          # JWT authentication middleware
│   ├── repository/                 # Postgres data access
│   └── service/                    # Business logic and OpenRouter client
├── migrations/                     # SQL up/down migrations
├── web/                            # Vue 3 + Tailwind frontend
│   ├── src/views/                  # Page components (login, transform, history, etc.)
│   ├── src/components/             # Shared UI (layout, modal)
│   ├── src/api/client.ts           # Fetch wrapper and types
│   └── dist/                       # Production build output
├── docs/                           # Project documentation
├── Dockerfile                      # Multi-stage API + web image build
├── docker-compose.yml              # postgres + api + web services
├── nginx.conf.template             # nginx /api proxy to Go API
├── run-on-docker.ps1               # Build and deploy Docker stack (local or SSH)
├── .dockerignore                   # Docker build context exclusions
├── go.mod                          # Go module definition
└── README.md                       # Setup and usage guide
```
