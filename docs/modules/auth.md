# Auth module

**Package:** `internal/service` + `internal/middleware`

Handles user login, JWT issuance/validation, and default user seeding on first boot.

## Key functions

- `AuthService.EnsureDefaultUser` — creates the initial user if the table is empty
- `AuthService.Login` — validates credentials, returns JWT
- `AuthService.ValidateToken` — parses and verifies JWT claims
- `middleware.JWTAuth` — Gin middleware protecting `/api/v1/*` routes

## Dependencies

- `repository.UserRepository`
- `golang.org/x/crypto/bcrypt` for password hashing
- `github.com/golang-jwt/jwt/v5`
