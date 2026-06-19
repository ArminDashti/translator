package service

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/armin/translator/internal/domain"
	"github.com/armin/translator/internal/repository"
)

type TranslationService struct {
	operationRepo   *repository.OperationCatalogRepository
	translationRepo *repository.TranslationRepository
	settingsService *SettingsService
	instructionSvc  *InstructionService
	openRouter      *OpenRouterClient
}

func NewTranslationService(
	operationRepo *repository.OperationCatalogRepository,
	translationRepo *repository.TranslationRepository,
	settingsService *SettingsService,
	instructionSvc *InstructionService,
	openRouter *OpenRouterClient,
) *TranslationService {
	return &TranslationService{
		operationRepo:   operationRepo,
		translationRepo: translationRepo,
		settingsService: settingsService,
		instructionSvc:  instructionSvc,
		openRouter:      openRouter,
	}
}

func (s *TranslationService) Translate(ctx context.Context, operationID uuid.UUID, text string, modelID *uuid.UUID) (*domain.Translation, error) {
	operation, err := s.operationRepo.GetByID(ctx, operationID)
	if err != nil {
		return nil, err
	}
	if !operation.IsActive {
		return nil, fmt.Errorf("operation is inactive")
	}

	resolvedModelID, model, err := s.settingsService.ResolveModelID(ctx, modelID)
	if err != nil {
		return nil, err
	}

	systemPrompt, err := s.instructionSvc.BuildSystemPrompt(operation.Slug)
	if err != nil {
		return nil, err
	}

	candidates, err := s.openRouter.Complete(ctx, model.OpenRouterID, systemPrompt, text)
	if err != nil {
		return nil, err
	}

	translation, err := s.translationRepo.Create(ctx, operationID, resolvedModelID, text, candidates)
	if err != nil {
		return nil, err
	}

	translation.OperationSlug = operation.Slug
	translation.ModelSlug = model.Slug
	return translation, nil
}

func (s *TranslationService) Get(ctx context.Context, id uuid.UUID) (*domain.Translation, error) {
	return s.translationRepo.GetByID(ctx, id)
}

func (s *TranslationService) List(ctx context.Context, operationID *uuid.UUID, limit, offset int) ([]domain.Translation, error) {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	return s.translationRepo.List(ctx, operationID, limit, offset)
}

func (s *TranslationService) SelectCandidate(ctx context.Context, id uuid.UUID, selected int) (*domain.Translation, error) {
	if selected < 1 || selected > 3 {
		return nil, fmt.Errorf("selected_candidate must be 1, 2, or 3")
	}
	return s.translationRepo.UpdateSelectedCandidate(ctx, id, selected)
}

type ReviewService struct {
	reviewRepo      *repository.ReviewRepository
	translationRepo *repository.TranslationRepository
}

func NewReviewService(reviewRepo *repository.ReviewRepository, translationRepo *repository.TranslationRepository) *ReviewService {
	return &ReviewService{reviewRepo: reviewRepo, translationRepo: translationRepo}
}

func (s *ReviewService) Create(ctx context.Context, translationID uuid.UUID, rating int, comment *string, selectedCandidate *int) (*domain.Review, error) {
	exists, err := s.translationRepo.Exists(ctx, translationID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, repository.ErrNotFound
	}

	if selectedCandidate != nil {
		if *selectedCandidate < 1 || *selectedCandidate > 3 {
			return nil, fmt.Errorf("selected_candidate must be 1, 2, or 3")
		}
		if err := s.translationRepo.SetSelectedCandidate(ctx, translationID, *selectedCandidate); err != nil {
			return nil, err
		}
	}

	return s.reviewRepo.Create(ctx, translationID, rating, comment, selectedCandidate)
}

func (s *ReviewService) Get(ctx context.Context, id uuid.UUID) (*domain.Review, error) {
	return s.reviewRepo.GetByID(ctx, id)
}

func (s *ReviewService) List(ctx context.Context, translationID *uuid.UUID, limit, offset int) ([]domain.Review, error) {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	return s.reviewRepo.List(ctx, translationID, limit, offset)
}

type OperationService struct {
	repo *repository.OperationCatalogRepository
}

func NewOperationService(repo *repository.OperationCatalogRepository) *OperationService {
	return &OperationService{repo: repo}
}

func (s *OperationService) List(ctx context.Context) ([]domain.TranslationOperation, error) {
	return s.repo.List(ctx)
}

func (s *OperationService) Get(ctx context.Context, id uuid.UUID) (*domain.TranslationOperation, error) {
	return s.repo.GetByID(ctx, id)
}
