package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/armin/translator/internal/domain"
	"github.com/armin/translator/internal/repository"
)

type TransformRequest struct {
	Operation string `json:"operation"`
	Text      string `json:"text"`
	Direction string `json:"direction"`
	Mode      string `json:"mode"`
	MovieName string `json:"movie_name"`
	Language  string `json:"language"`
	Style     string `json:"style"`
}

type TransformService struct {
	historyRepo     *repository.HistoryRepository
	settingsService *SettingsService
	instructionSvc  *InstructionService
	openRouter      *OpenRouterClient
}

func NewTransformService(
	historyRepo *repository.HistoryRepository,
	settingsService *SettingsService,
	instructionSvc *InstructionService,
	openRouter *OpenRouterClient,
) *TransformService {
	return &TransformService{
		historyRepo:     historyRepo,
		settingsService: settingsService,
		instructionSvc:  instructionSvc,
		openRouter:      openRouter,
	}
}

func (s *TransformService) Transform(ctx context.Context, req TransformRequest) (*domain.TransformResult, error) {
	text := strings.TrimSpace(req.Text)
	if text == "" {
		return nil, fmt.Errorf("text is required")
	}

	historyType, instructionKey, userText, metadata, err := s.resolveTransform(req, text)
	if err != nil {
		return nil, err
	}

	settings, err := s.settingsService.Get(ctx)
	if err != nil {
		return nil, err
	}

	systemPrompt, err := s.instructionSvc.BuildPrompt(ctx, instructionKey)
	if err != nil {
		return nil, err
	}

	result, err := s.openRouter.Complete(ctx, settings.OpenRouterAPIKey, settings.ModelName, systemPrompt, userText)
	if err != nil {
		return nil, err
	}

	record := domain.HistoryRecord{
		Type:           historyType,
		InputText:      text,
		ResultText:     result,
		Model:          settings.ModelName,
		InstructionKey: instructionKey,
		Metadata:       repository.MetadataJSON(metadata),
	}

	saved, err := s.historyRepo.Create(ctx, record)
	if err != nil {
		return nil, err
	}

	return &domain.TransformResult{
		ID:             saved.ID,
		Type:           saved.Type,
		TypeDisplay:    saved.TypeDisplay,
		InputText:      saved.InputText,
		ResultText:     saved.ResultText,
		Model:          saved.Model,
		InstructionKey: saved.InstructionKey,
		CreatedAt:      saved.CreatedAt,
		FormattedDate:  saved.FormattedDate,
	}, nil
}

func (s *TransformService) resolveTransform(req TransformRequest, text string) (domain.HistoryType, string, string, map[string]string, error) {
	op := strings.ToLower(strings.TrimSpace(req.Operation))
	metadata := map[string]string{}

	switch op {
	case "translate":
		dir := strings.ToLower(req.Direction)
		mode := strings.ToLower(req.Mode)
		if dir == "en-fa" {
			key := fmt.Sprintf("en-to-fa-%s", mode)
			if mode == "movie" {
				movie := strings.TrimSpace(req.MovieName)
				if movie == "" {
					return "", "", "", nil, fmt.Errorf("movie name is required for movie mode")
				}
				metadata["movie_name"] = movie
				return domain.HistoryTypeEnFa, key, fmt.Sprintf("Movie: %s\n\n%s", movie, text), metadata, nil
			}
			if !isValidEnFaMode(mode) {
				return "", "", "", nil, fmt.Errorf("invalid translate mode: %s", mode)
			}
			return domain.HistoryTypeEnFa, key, text, metadata, nil
		}
		if dir == "fa-en" {
			key := fmt.Sprintf("fa-to-en-%s", mode)
			if !isValidFaEnMode(mode) {
				return "", "", "", nil, fmt.Errorf("invalid translate mode: %s", mode)
			}
			return domain.HistoryTypeFaEn, key, text, metadata, nil
		}
		return "", "", "", nil, fmt.Errorf("invalid translate direction: %s", req.Direction)

	case "simplify":
		return domain.HistoryTypeSimplify, "simplify-en", text, metadata, nil

	case "term":
		lang := strings.ToLower(req.Language)
		style := strings.ToLower(req.Style)
		key := fmt.Sprintf("term-for-%s", style)
		if !isValidTermStyle(style) {
			return "", "", "", nil, fmt.Errorf("invalid term style: %s", style)
		}
		switch lang {
		case "en":
			return domain.HistoryTypeTermEn, key, "Find an English term for this description:\n\n" + text, metadata, nil
		case "fa":
			return domain.HistoryTypeTermFa, key, "Find a Persian term for this description:\n\n" + text, metadata, nil
		default:
			return "", "", "", nil, fmt.Errorf("invalid term language: %s", req.Language)
		}

	case "refine":
		style := strings.ToLower(req.Style)
		key := fmt.Sprintf("refine-to-%s", style)
		if !isValidRefineStyle(style) {
			return "", "", "", nil, fmt.Errorf("invalid refine style: %s", style)
		}
		return domain.HistoryTypeRefine, key, text, metadata, nil

	case "symptoms":
		return domain.HistoryTypeSymptoms, "symptoms", text, metadata, nil

	default:
		return "", "", "", nil, fmt.Errorf("invalid operation: %s", req.Operation)
	}
}

func isValidEnFaMode(mode string) bool {
	switch mode {
	case "general", "movie", "formal", "scientific", "music":
		return true
	default:
		return false
	}
}

func isValidFaEnMode(mode string) bool {
	switch mode {
	case "general", "formal", "scientific":
		return true
	default:
		return false
	}
}

func isValidTermStyle(style string) bool {
	switch style {
	case "everyday", "formal", "slang":
		return true
	default:
		return false
	}
}

func isValidRefineStyle(style string) bool {
	return isValidTermStyle(style)
}

type HistoryService struct {
	repo *repository.HistoryRepository
}

func NewHistoryService(repo *repository.HistoryRepository) *HistoryService {
	return &HistoryService{repo: repo}
}

func (s *HistoryService) List(ctx context.Context, sortBy, sortOrder string, limit, offset int) ([]domain.HistoryRecord, error) {
	return s.repo.List(ctx, sortBy, sortOrder, limit, offset)
}

func (s *HistoryService) Get(ctx context.Context, id string) (*domain.HistoryRecord, error) {
	uid, err := uuid.Parse(id)
	if err != nil {
		return nil, fmt.Errorf("invalid id")
	}
	return s.repo.GetByID(ctx, uid)
}

func (s *HistoryService) Delete(ctx context.Context, id string) error {
	uid, err := uuid.Parse(id)
	if err != nil {
		return fmt.Errorf("invalid id")
	}
	return s.repo.Delete(ctx, uid)
}

type StatsService struct {
	repo *repository.HistoryRepository
}

func NewStatsService(repo *repository.HistoryRepository) *StatsService {
	return &StatsService{repo: repo}
}

func (s *StatsService) Get(ctx context.Context) (*domain.StatsResponse, error) {
	now := time.Now()
	startToday := startOfDay(now)
	startYesterday := startToday.AddDate(0, 0, -1)
	startWeek := startToday.AddDate(0, 0, -6)
	startMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())

	today, err := s.repo.CountByPeriod(ctx, &startToday, nil)
	if err != nil {
		return nil, err
	}
	yesterday, err := s.repo.CountByPeriod(ctx, &startYesterday, &startToday)
	if err != nil {
		return nil, err
	}
	week, err := s.repo.CountByPeriod(ctx, &startWeek, nil)
	if err != nil {
		return nil, err
	}
	month, err := s.repo.CountByPeriod(ctx, &startMonth, nil)
	if err != nil {
		return nil, err
	}
	allTime, err := s.repo.CountByPeriod(ctx, nil, nil)
	if err != nil {
		return nil, err
	}

	return &domain.StatsResponse{
		Today:     today,
		Yesterday: yesterday,
		Week:      week,
		Month:     month,
		AllTime:   allTime,
	}, nil
}

func startOfDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}
