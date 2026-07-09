# syntax=docker/dockerfile:1

# --- API (Go) ---
FROM golang:1.22-alpine AS api-build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY migrations/ ./migrations/
RUN CGO_ENABLED=0 go build -o /out/server ./cmd/server

FROM alpine:3.20 AS api
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=api-build /out/server /app/server
COPY --from=api-build /src/migrations /app/migrations
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]

# --- Web (Vue + nginx) ---
FROM node:22-alpine AS web-build
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM nginx:alpine AS web
COPY --from=web-build /src/web/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
ENV API_HOST=translator
ENV API_PORT=8080
EXPOSE 80
