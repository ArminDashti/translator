package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/armin/translator/internal/domain"
)

type SettingsRepository struct {
	pool *pgxpool.Pool
}

func NewSettingsRepository(pool *pgxpool.Pool) *SettingsRepository {
	return &SettingsRepository{pool: pool}
}

func (r *SettingsRepository) Get(ctx context.Context) (*domain.AppSettings, error) {
	var s domain.AppSettings
	err := r.pool.QueryRow(ctx, `
		SELECT openrouter_api_key, model_name, updated_at FROM app_settings WHERE id = 1
	`).Scan(&s.OpenRouterAPIKey, &s.ModelName, &s.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("get settings: %w", err)
	}
	return &s, nil
}

func (r *SettingsRepository) Update(ctx context.Context, apiKey, modelName *string) (*domain.AppSettings, error) {
	if apiKey != nil && modelName != nil {
		_, err := r.pool.Exec(ctx, `
			UPDATE app_settings SET openrouter_api_key = $1, model_name = $2, updated_at = now() WHERE id = 1
		`, *apiKey, *modelName)
		if err != nil {
			return nil, fmt.Errorf("update settings: %w", err)
		}
	} else if apiKey != nil {
		_, err := r.pool.Exec(ctx, `
			UPDATE app_settings SET openrouter_api_key = $1, updated_at = now() WHERE id = 1
		`, *apiKey)
		if err != nil {
			return nil, fmt.Errorf("update settings: %w", err)
		}
	} else if modelName != nil {
		_, err := r.pool.Exec(ctx, `
			UPDATE app_settings SET model_name = $1, updated_at = now() WHERE id = 1
		`, *modelName)
		if err != nil {
			return nil, fmt.Errorf("update settings: %w", err)
		}
	}
	return r.Get(ctx)
}

func (r *SettingsRepository) ClearAllData(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM history`)
	return err
}
