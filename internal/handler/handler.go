package handler

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/armin/translator/internal/domain"
	"github.com/armin/translator/internal/repository"
	"github.com/armin/translator/internal/service"
)

type Handler struct {
	settingsService    *service.SettingsService
	operationService   *service.OperationService
	translationService *service.TranslationService
	reviewService      *service.ReviewService
	instructionService *service.InstructionService
}

func New(
	settingsService *service.SettingsService,
	operationService *service.OperationService,
	translationService *service.TranslationService,
	reviewService *service.ReviewService,
	instructionService *service.InstructionService,
) *Handler {
	return &Handler{
		settingsService:    settingsService,
		operationService:   operationService,
		translationService: translationService,
		reviewService:      reviewService,
		instructionService: instructionService,
	}
}

func (h *Handler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *Handler) handleError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, repository.ErrNotFound):
		c.JSON(http.StatusNotFound, domain.APIError{Error: err.Error(), Code: "NOT_FOUND"})
	case errors.Is(err, service.ErrNoDefaultModel):
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "NO_DEFAULT_MODEL"})
	case errors.Is(err, service.ErrModelInactive):
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "MODEL_INACTIVE"})
	default:
		if err != nil && strings.Contains(err.Error(), "model not found") {
			c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "MODEL_NOT_FOUND"})
			return
		}
		if err != nil && err.Error() == "cannot delete default model; reassign default_model_id first" {
			c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "DEFAULT_MODEL_DELETE"})
			return
		}
		if err != nil && (strings.Contains(err.Error(), "parse candidates") || strings.Contains(err.Error(), "incomplete candidates")) {
			c.JSON(http.StatusUnprocessableEntity, domain.APIError{Error: err.Error(), Code: "LLM_PARSE_FAILURE"})
			return
		}
		if err != nil && strings.Contains(err.Error(), "openrouter") {
			c.JSON(http.StatusBadGateway, domain.APIError{Error: err.Error(), Code: "OPENROUTER_ERROR"})
			return
		}
		c.JSON(http.StatusInternalServerError, domain.APIError{Error: err.Error(), Code: "INTERNAL_ERROR"})
	}
}

func parseUUIDParam(c *gin.Context, name string) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.Param(name))
	if err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: "invalid " + name, Code: "INVALID_ID"})
		return uuid.Nil, false
	}
	return id, true
}
