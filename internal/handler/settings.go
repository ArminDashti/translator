package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/armin/translator/internal/domain"
)

type patchSettingsRequest struct {
	OpenRouterAPIKey *string `json:"openrouter_api_key"`
	ModelName        *string `json:"model_name"`
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

	settings, err := h.settingsService.Update(c.Request.Context(), req.OpenRouterAPIKey, req.ModelName)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, settings)
}

func (h *Handler) ClearData(c *gin.Context) {
	if err := h.settingsService.ClearAllData(c.Request.Context()); err != nil {
		h.handleError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
