package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/armin/translator/internal/domain"
	"github.com/armin/translator/internal/repository"
)

type InstructionService struct {
	repo *repository.InstructionRepository
}

func NewInstructionService(repo *repository.InstructionRepository) *InstructionService {
	return &InstructionService{repo: repo}
}

func (s *InstructionService) EnsureDefaults(ctx context.Context) error {
	for _, key := range domain.InstructionKeys {
		existing, err := s.repo.Get(ctx, key)
		if err == nil && existing != nil {
			continue
		}
		if _, err := s.repo.Upsert(ctx, key, defaultInstructionContent(key)); err != nil {
			return err
		}
	}
	return nil
}

func (s *InstructionService) List(ctx context.Context) ([]domain.Instruction, error) {
	return s.repo.List(ctx)
}

func (s *InstructionService) Get(ctx context.Context, key string) (*domain.Instruction, error) {
	return s.repo.Get(ctx, key)
}

func (s *InstructionService) Update(ctx context.Context, key, content string) (*domain.Instruction, error) {
	return s.repo.Upsert(ctx, key, content)
}

func defaultInstructionContent(key string) string {
	base := "Respond with only the final result text. No explanations, labels, or markdown."
	switch key {
	case "en-to-fa-general":
		return base + "\n\nTranslate the English input into natural, everyday Persian."
	case "en-to-fa-movie":
		return base + "\n\nTranslate the English input into Persian dialogue suitable for the named movie's tone and era."
	case "en-to-fa-formal":
		return base + "\n\nTranslate the English input into formal, polished Persian."
	case "en-to-fa-scientific":
		return base + "\n\nTranslate the English input into accurate scientific Persian terminology."
	case "en-to-fa-music":
		return base + "\n\nTranslate the English input into lyrical Persian suitable for song lyrics."
	case "fa-to-en-general":
		return base + "\n\nTranslate the Persian input into natural, everyday English."
	case "fa-to-en-formal":
		return base + "\n\nTranslate the Persian input into formal, professional English."
	case "fa-to-en-scientific":
		return base + "\n\nTranslate the Persian input into accurate scientific English."
	case "simplify-en":
		return base + "\n\nSimplify the English sentence while preserving meaning."
	case "refine-to-everyday":
		return base + "\n\nRewrite the English sentence into clear everyday language."
	case "refine-to-formal":
		return base + "\n\nRewrite the English sentence into formal, professional English."
	case "refine-to-slang":
		return base + "\n\nRewrite the English sentence using casual slang while keeping the meaning."
	case "symptoms":
		return base + "\n\nList common symptoms, signs, and related context for the given English word or term."
	case "term-for-everyday":
		return base + "\n\nGiven a description, return the best matching word or short phrase in everyday language."
	case "term-for-formal":
		return base + "\n\nGiven a description, return the best matching formal word or short phrase."
	case "term-for-slang":
		return base + "\n\nGiven a description, return the best matching slang word or short phrase."
	default:
		return base
	}
}

func (s *InstructionService) BuildPrompt(ctx context.Context, key string) (string, error) {
	instruction, err := s.repo.Get(ctx, key)
	if err != nil {
		return "", fmt.Errorf("instruction %s: %w", key, err)
	}
	return strings.TrimSpace(instruction.Content), nil
}
