package service

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/armin/translator/internal/domain"
	"github.com/armin/translator/internal/repository"
)

var (
	ErrNoDefaultModel = errors.New("no default model configured")
	ErrModelInactive  = errors.New("model is inactive")
)

type SettingsService struct {
	settingsRepo *repository.SettingsRepository
	modelRepo    *repository.ModelCatalogRepository
}

func NewSettingsService(settingsRepo *repository.SettingsRepository, modelRepo *repository.ModelCatalogRepository) *SettingsService {
	return &SettingsService{settingsRepo: settingsRepo, modelRepo: modelRepo}
}

func (s *SettingsService) Get(ctx context.Context) (*domain.AppSettings, error) {
	return s.settingsRepo.Get(ctx)
}

func (s *SettingsService) Update(ctx context.Context, defaultModelID *uuid.UUID) (*domain.AppSettings, error) {
	return s.settingsRepo.UpdateDefaultModel(ctx, defaultModelID)
}

func (s *SettingsService) ListModels(ctx context.Context) ([]domain.LLMModel, error) {
	return s.modelRepo.List(ctx)
}

func (s *SettingsService) CreateModel(ctx context.Context, slug, openrouterID, displayName string) (*domain.LLMModel, error) {
	return s.modelRepo.Create(ctx, slug, openrouterID, displayName)
}

func (s *SettingsService) UpdateModel(ctx context.Context, id uuid.UUID, slug, openrouterID, displayName string, isActive bool) (*domain.LLMModel, error) {
	return s.modelRepo.Update(ctx, id, slug, openrouterID, displayName, isActive)
}

func (s *SettingsService) DeleteModel(ctx context.Context, id uuid.UUID) error {
	return s.modelRepo.Delete(ctx, id, s.settingsRepo)
}

func (s *SettingsService) ResolveModelID(ctx context.Context, modelID *uuid.UUID) (uuid.UUID, *domain.LLMModel, error) {
	if modelID != nil {
		model, err := s.modelRepo.GetByID(ctx, *modelID)
		if err != nil {
			return uuid.Nil, nil, err
		}
		if !model.IsActive {
			return uuid.Nil, nil, ErrModelInactive
		}
		return model.ID, model, nil
	}

	settings, err := s.settingsRepo.Get(ctx)
	if err != nil {
		return uuid.Nil, nil, err
	}
	if settings.DefaultModelID == nil {
		return uuid.Nil, nil, ErrNoDefaultModel
	}

	model, err := s.modelRepo.GetByID(ctx, *settings.DefaultModelID)
	if err != nil {
		return uuid.Nil, nil, err
	}
	if !model.IsActive {
		return uuid.Nil, nil, ErrModelInactive
	}
	return model.ID, model, nil
}
