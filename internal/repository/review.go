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

type ReviewRepository struct {
	pool *pgxpool.Pool
}

func NewReviewRepository(pool *pgxpool.Pool) *ReviewRepository {
	return &ReviewRepository{pool: pool}
}

func (r *ReviewRepository) Create(ctx context.Context, translationID uuid.UUID, rating int, comment *string, selectedCandidate *int) (*domain.Review, error) {
	var review domain.Review
	err := r.pool.QueryRow(ctx, `
		INSERT INTO reviews (translation_id, rating, comment, selected_candidate)
		VALUES ($1, $2, $3, $4)
		RETURNING id, translation_id, rating, comment, selected_candidate, created_at
	`, translationID, rating, comment, selectedCandidate).Scan(
		&review.ID, &review.TranslationID, &review.Rating, &review.Comment, &review.SelectedCandidate, &review.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create review: %w", err)
	}

	translation, err := r.loadTranslation(ctx, translationID)
	if err != nil {
		return nil, err
	}
	review.Translation = translation
	return &review, nil
}

func (r *ReviewRepository) GetByID(ctx context.Context, id uuid.UUID) (*domain.Review, error) {
	var review domain.Review
	err := r.pool.QueryRow(ctx, `
		SELECT id, translation_id, rating, comment, selected_candidate, created_at
		FROM reviews WHERE id = $1
	`, id).Scan(&review.ID, &review.TranslationID, &review.Rating, &review.Comment, &review.SelectedCandidate, &review.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get review: %w", err)
	}

	translation, err := r.loadTranslation(ctx, review.TranslationID)
	if err != nil {
		return nil, err
	}
	review.Translation = translation
	return &review, nil
}

func (r *ReviewRepository) List(ctx context.Context, translationID *uuid.UUID, limit, offset int) ([]domain.Review, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, translation_id, rating, comment, selected_candidate, created_at
		FROM reviews
		WHERE ($1::uuid IS NULL OR translation_id = $1)
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, translationID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list reviews: %w", err)
	}
	defer rows.Close()

	var reviews []domain.Review
	for rows.Next() {
		var review domain.Review
		if err := rows.Scan(&review.ID, &review.TranslationID, &review.Rating, &review.Comment, &review.SelectedCandidate, &review.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan review: %w", err)
		}
		translation, err := r.loadTranslation(ctx, review.TranslationID)
		if err != nil {
			return nil, err
		}
		review.Translation = translation
		reviews = append(reviews, review)
	}
	return reviews, rows.Err()
}

func (r *ReviewRepository) loadTranslation(ctx context.Context, id uuid.UUID) (*domain.Translation, error) {
	var t domain.Translation
	err := r.pool.QueryRow(ctx, `
		SELECT t.id, t.operation_id, o.slug, t.input_text, t.model_id, m.slug,
		       t.candidate1, t.candidate2, t.candidate3, t.selected_candidate, t.created_at
		FROM translations t
		INNER JOIN translation_operations o ON o.id = t.operation_id
		INNER JOIN llm_models m ON m.id = t.model_id
		WHERE t.id = $1
	`, id).Scan(
		&t.ID, &t.OperationID, &t.OperationSlug, &t.InputText, &t.ModelID, &t.ModelSlug,
		&t.Candidate1, &t.Candidate2, &t.Candidate3, &t.SelectedCandidate, &t.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("load translation for review: %w", err)
	}
	return &t, nil
}
