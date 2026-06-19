package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/armin/translator/internal/domain"
)

func queryInt(c *gin.Context, key string, defaultVal int) int {
	v := c.Query(key)
	if v == "" {
		return defaultVal
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return defaultVal
	}
	return n
}

type patchSettingsRequest struct {
	DefaultModelID *uuid.UUID `json:"default_model_id"`
}

func (h *Handler) GetSettings(c *gin.Context) {
	settings, err := h.settingsService.Get(c.Request.Context())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, settings)
}

func (h *Handler) PatchSettings(c *gin.Context) {
	var req patchSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	settings, err := h.settingsService.Update(c.Request.Context(), req.DefaultModelID)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, settings)
}

type createModelRequest struct {
	Slug         string `json:"slug" binding:"required"`
	OpenRouterID string `json:"openrouter_id" binding:"required"`
	DisplayName  string `json:"display_name" binding:"required"`
}

func (h *Handler) ListModels(c *gin.Context) {
	models, err := h.settingsService.ListModels(c.Request.Context())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, models)
}

func (h *Handler) CreateModel(c *gin.Context) {
	var req createModelRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	model, err := h.settingsService.CreateModel(c.Request.Context(), req.Slug, req.OpenRouterID, req.DisplayName)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, model)
}

type updateModelRequest struct {
	Slug         string `json:"slug" binding:"required"`
	OpenRouterID string `json:"openrouter_id" binding:"required"`
	DisplayName  string `json:"display_name" binding:"required"`
	IsActive     bool   `json:"is_active"`
}

func (h *Handler) UpdateModel(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	var req updateModelRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	model, err := h.settingsService.UpdateModel(c.Request.Context(), id, req.Slug, req.OpenRouterID, req.DisplayName, req.IsActive)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, model)
}

func (h *Handler) DeleteModel(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	if err := h.settingsService.DeleteModel(c.Request.Context(), id); err != nil {
		h.handleError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
