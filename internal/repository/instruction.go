package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/armin/translator/internal/domain"
)

type InstructionRepository struct {
	pool *pgxpool.Pool
}

func NewInstructionRepository(pool *pgxpool.Pool) *InstructionRepository {
	return &InstructionRepository{pool: pool}
}

func (r *InstructionRepository) List(ctx context.Context) ([]domain.Instruction, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT key, content, updated_at FROM instructions ORDER BY key ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("list instructions: %w", err)
	}
	defer rows.Close()

	var items []domain.Instruction
	for rows.Next() {
		var i domain.Instruction
		if err := rows.Scan(&i.Key, &i.Content, &i.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, i)
	}
	return items, rows.Err()
}

func (r *InstructionRepository) Get(ctx context.Context, key string) (*domain.Instruction, error) {
	var i domain.Instruction
	err := r.pool.QueryRow(ctx, `
		SELECT key, content, updated_at FROM instructions WHERE key = $1
	`, key).Scan(&i.Key, &i.Content, &i.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get instruction: %w", err)
	}
	return &i, nil
}

func (r *InstructionRepository) Upsert(ctx context.Context, key, content string) (*domain.Instruction, error) {
	var i domain.Instruction
	err := r.pool.QueryRow(ctx, `
		INSERT INTO instructions (key, content) VALUES ($1, $2)
		ON CONFLICT (key) DO UPDATE SET content = EXCLUDED.content, updated_at = now()
		RETURNING key, content, updated_at
	`, key, content).Scan(&i.Key, &i.Content, &i.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("upsert instruction: %w", err)
	}
	return &i, nil
}
