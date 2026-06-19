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

type OperationCatalogRepository struct {
	pool *pgxpool.Pool
}

func NewOperationCatalogRepository(pool *pgxpool.Pool) *OperationCatalogRepository {
	return &OperationCatalogRepository{pool: pool}
}

func (r *OperationCatalogRepository) List(ctx context.Context) ([]domain.TranslationOperation, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, slug, display_name, description, is_active, created_at
		FROM translation_operations WHERE is_active = true ORDER BY created_at ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("list operations: %w", err)
	}
	defer rows.Close()

	var ops []domain.TranslationOperation
	for rows.Next() {
		var o domain.TranslationOperation
		if err := rows.Scan(&o.ID, &o.Slug, &o.DisplayName, &o.Description, &o.IsActive, &o.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan operation: %w", err)
		}
		ops = append(ops, o)
	}
	return ops, rows.Err()
}

func (r *OperationCatalogRepository) GetByID(ctx context.Context, id uuid.UUID) (*domain.TranslationOperation, error) {
	var o domain.TranslationOperation
	err := r.pool.QueryRow(ctx, `
		SELECT id, slug, display_name, description, is_active, created_at
		FROM translation_operations WHERE id = $1
	`, id).Scan(&o.ID, &o.Slug, &o.DisplayName, &o.Description, &o.IsActive, &o.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get operation: %w", err)
	}
	return &o, nil
}
