package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	Port            string
	APIToken        string
	DatabaseURL     string
	OpenRouterAPIKey string
	InstructionsDir string
}

func Load() (*Config, error) {
	_ = godotenv.Load()

	cfg := &Config{
		Port:            getEnv("PORT", "8080"),
		APIToken:        os.Getenv("API_TOKEN"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		OpenRouterAPIKey: os.Getenv("OPENROUTER_API_KEY"),
		InstructionsDir: getEnv("INSTRUCTIONS_DIR", "./instructions"),
	}

	if cfg.APIToken == "" {
		return nil, fmt.Errorf("API_TOKEN is required")
	}
	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.OpenRouterAPIKey == "" {
		return nil, fmt.Errorf("OPENROUTER_API_KEY is required")
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
