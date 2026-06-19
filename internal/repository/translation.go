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

type TranslationRepository struct {
	pool *pgxpool.Pool
}

func NewTranslationRepository(pool *pgxpool.Pool) *TranslationRepository {
	return &TranslationRepository{pool: pool}
}

func (r *TranslationRepository) Create(ctx context.Context, operationID, modelID uuid.UUID, inputText string, candidates domain.TranslationCandidates) (*domain.Translation, error) {
	var t domain.Translation
	err := r.pool.QueryRow(ctx, `
		INSERT INTO translations (operation_id, input_text, model_id, candidate1, candidate2, candidate3)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, operation_id, input_text, model_id, candidate1, candidate2, candidate3, selected_candidate, created_at
	`, operationID, inputText, modelID, candidates.Candidate1, candidates.Candidate2, candidates.Candidate3).Scan(
		&t.ID, &t.OperationID, &t.InputText, &t.ModelID,
		&t.Candidate1, &t.Candidate2, &t.Candidate3, &t.SelectedCandidate, &t.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create translation: %w", err)
	}
	return &t, nil
}

func (r *TranslationRepository) GetByID(ctx context.Context, id uuid.UUID) (*domain.Translation, error) {
	return r.scanOne(ctx, `
		SELECT t.id, t.operation_id, o.slug, t.input_text, t.model_id, m.slug,
		       t.candidate1, t.candidate2, t.candidate3, t.selected_candidate, t.created_at
		FROM translations t
		JOIN translation_operations o ON o.id = t.operation_id
		JOIN llm_models m ON m.id = t.model_id
		WHERE t.id = $1
	`, id)
}

func (r *TranslationRepository) List(ctx context.Context, operationID *uuid.UUID, limit, offset int) ([]domain.Translation, error) {
	query := `
		SELECT t.id, t.operation_id, o.slug, t.input_text, t.model_id, m.slug,
		       t.candidate1, t.candidate2, t.candidate3, t.selected_candidate, t.created_at
		FROM translations t
		JOIN translation_operations o ON o.id = t.operation_id
		JOIN llm_models m ON m.id = t.model_id
		WHERE ($1::uuid IS NULL OR t.operation_id = $1)
		ORDER BY t.created_at DESC
		LIMIT $2 OFFSET $3
	`
	var opID *uuid.UUID = operationID
	rows, err := r.pool.Query(ctx, query, opID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list translations: %w", err)
	}
	defer rows.Close()

	return r.scanRows(rows)
}

func (r *TranslationRepository) UpdateSelectedCandidate(ctx context.Context, id uuid.UUID, selected int) (*domain.Translation, error) {
	tag, err := r.pool.Exec(ctx, `UPDATE translations SET selected_candidate = $2 WHERE id = $1`, id, selected)
	if err != nil {
		return nil, fmt.Errorf("update selected candidate: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrNotFound
	}
	return r.GetByID(ctx, id)
}

func (r *TranslationRepository) scanOne(ctx context.Context, query string, args ...any) (*domain.Translation, error) {
	var t domain.Translation
	err := r.pool.QueryRow(ctx, query, args...).Scan(
		&t.ID, &t.OperationID, &t.OperationSlug, &t.InputText, &t.ModelID, &t.ModelSlug,
		&t.Candidate1, &t.Candidate2, &t.Candidate3, &t.SelectedCandidate, &t.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan translation: %w", err)
	}
	return &t, nil
}

func (r *TranslationRepository) scanRows(rows pgx.Rows) ([]domain.Translation, error) {
	var items []domain.Translation
	for rows.Next() {
		var t domain.Translation
		if err := rows.Scan(
			&t.ID, &t.OperationID, &t.OperationSlug, &t.InputText, &t.ModelID, &t.ModelSlug,
			&t.Candidate1, &t.Candidate2, &t.Candidate3, &t.SelectedCandidate, &t.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan translation row: %w", err)
		}
		items = append(items, t)
	}
	return items, rows.Err()
}

func (r *TranslationRepository) Exists(ctx context.Context, id uuid.UUID) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM translations WHERE id = $1)`, id).Scan(&exists)
	return exists, err
}

func (r *TranslationRepository) SetSelectedCandidate(ctx context.Context, id uuid.UUID, selected int) error {
	tag, err := r.pool.Exec(ctx, `UPDATE translations SET selected_candidate = $2 WHERE id = $1`, id, selected)
	if err != nil {
		return fmt.Errorf("set selected candidate: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
