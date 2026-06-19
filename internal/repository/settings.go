package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/armin/translator/internal/domain"
)

var ErrNotFound = errors.New("not found")

type SettingsRepository struct {
	pool *pgxpool.Pool
}

func NewSettingsRepository(pool *pgxpool.Pool) *SettingsRepository {
	return &SettingsRepository{pool: pool}
}

func (r *SettingsRepository) Get(ctx context.Context) (*domain.AppSettings, error) {
	var s domain.AppSettings
	err := r.pool.QueryRow(ctx, `
		SELECT default_model_id, updated_at FROM app_settings WHERE id = 1
	`).Scan(&s.DefaultModelID, &s.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("get settings: %w", err)
	}
	return &s, nil
}

func (r *SettingsRepository) UpdateDefaultModel(ctx context.Context, modelID *uuid.UUID) (*domain.AppSettings, error) {
	if modelID != nil {
		var exists bool
		err := r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM llm_models WHERE id = $1 AND is_active = true)`, *modelID).Scan(&exists)
		if err != nil {
			return nil, fmt.Errorf("check model: %w", err)
		}
		if !exists {
			return nil, fmt.Errorf("model not found or inactive")
		}
	}

	_, err := r.pool.Exec(ctx, `
		UPDATE app_settings SET default_model_id = $1, updated_at = now() WHERE id = 1
	`, modelID)
	if err != nil {
		return nil, fmt.Errorf("update settings: %w", err)
	}
	return r.Get(ctx)
}

type ModelCatalogRepository struct {
	pool *pgxpool.Pool
}

func NewModelCatalogRepository(pool *pgxpool.Pool) *ModelCatalogRepository {
	return &ModelCatalogRepository{pool: pool}
}

func (r *ModelCatalogRepository) List(ctx context.Context) ([]domain.LLMModel, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, slug, openrouter_id, display_name, is_active, created_at, updated_at
		FROM llm_models ORDER BY created_at ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("list models: %w", err)
	}
	defer rows.Close()

	var models []domain.LLMModel
	for rows.Next() {
		var m domain.LLMModel
		if err := rows.Scan(&m.ID, &m.Slug, &m.OpenRouterID, &m.DisplayName, &m.IsActive, &m.CreatedAt, &m.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan model: %w", err)
		}
		models = append(models, m)
	}
	return models, rows.Err()
}

func (r *ModelCatalogRepository) GetByID(ctx context.Context, id uuid.UUID) (*domain.LLMModel, error) {
	var m domain.LLMModel
	err := r.pool.QueryRow(ctx, `
		SELECT id, slug, openrouter_id, display_name, is_active, created_at, updated_at
		FROM llm_models WHERE id = $1
	`, id).Scan(&m.ID, &m.Slug, &m.OpenRouterID, &m.DisplayName, &m.IsActive, &m.CreatedAt, &m.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get model: %w", err)
	}
	return &m, nil
}

func (r *ModelCatalogRepository) Create(ctx context.Context, slug, openrouterID, displayName string) (*domain.LLMModel, error) {
	var m domain.LLMModel
	err := r.pool.QueryRow(ctx, `
		INSERT INTO llm_models (slug, openrouter_id, display_name)
		VALUES ($1, $2, $3)
		RETURNING id, slug, openrouter_id, display_name, is_active, created_at, updated_at
	`, slug, openrouterID, displayName).Scan(
		&m.ID, &m.Slug, &m.OpenRouterID, &m.DisplayName, &m.IsActive, &m.CreatedAt, &m.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create model: %w", err)
	}
	return &m, nil
}

func (r *ModelCatalogRepository) Update(ctx context.Context, id uuid.UUID, slug, openrouterID, displayName string, isActive bool) (*domain.LLMModel, error) {
	var m domain.LLMModel
	err := r.pool.QueryRow(ctx, `
		UPDATE llm_models
		SET slug = $2, openrouter_id = $3, display_name = $4, is_active = $5, updated_at = now()
		WHERE id = $1
		RETURNING id, slug, openrouter_id, display_name, is_active, created_at, updated_at
	`, id, slug, openrouterID, displayName, isActive).Scan(
		&m.ID, &m.Slug, &m.OpenRouterID, &m.DisplayName, &m.IsActive, &m.CreatedAt, &m.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update model: %w", err)
	}
	return &m, nil
}

func (r *ModelCatalogRepository) Delete(ctx context.Context, id uuid.UUID, settingsRepo *SettingsRepository) error {
	settings, err := settingsRepo.Get(ctx)
	if err != nil {
		return err
	}
	if settings.DefaultModelID != nil && *settings.DefaultModelID == id {
		return fmt.Errorf("cannot delete default model; reassign default_model_id first")
	}

	tag, err := r.pool.Exec(ctx, `DELETE FROM llm_models WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete model: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
