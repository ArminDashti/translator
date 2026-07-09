package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	Port            string
	JWTSecret       string
	DatabaseURL     string
	StaticDir       string
	DefaultUsername string
	DefaultPassword string
}

func Load() (*Config, error) {
	_ = godotenv.Load()

	cfg := &Config{
		Port:            getEnv("PORT", "8080"),
		JWTSecret:       os.Getenv("JWT_SECRET"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		StaticDir:       getEnv("STATIC_DIR", "./web/dist"),
		DefaultUsername: getEnv("DEFAULT_USERNAME", "armin"),
		DefaultPassword: getEnv("DEFAULT_PASSWORD", "Translator@2024"),
	}

	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}
	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
