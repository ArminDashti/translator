package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/armin/translator/internal/domain"
)

type translateRequest struct {
	OperationID uuid.UUID  `json:"operation_id" binding:"required"`
	Text        string     `json:"text" binding:"required"`
	ModelID     *uuid.UUID `json:"model_id"`
}

func (h *Handler) Translate(c *gin.Context) {
	var req translateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	result, err := h.translationService.Translate(c.Request.Context(), req.OperationID, req.Text, req.ModelID)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, result)
}

func (h *Handler) ListOperations(c *gin.Context) {
	ops, err := h.operationService.List(c.Request.Context())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, ops)
}

type patchTranslationRequest struct {
	SelectedCandidate int `json:"selected_candidate" binding:"required,min=1,max=3"`
}

func (h *Handler) PatchTranslation(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	var req patchTranslationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	result, err := h.translationService.SelectCandidate(c.Request.Context(), id, req.SelectedCandidate)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, result)
}

func (h *Handler) GetTranslation(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	result, err := h.translationService.Get(c.Request.Context(), id)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, result)
}

func (h *Handler) ListTranslations(c *gin.Context) {
	var operationID *uuid.UUID
	if opStr := c.Query("operation_id"); opStr != "" {
		id, err := uuid.Parse(opStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, domain.APIError{Error: "invalid operation_id", Code: "INVALID_ID"})
			return
		}
		operationID = &id
	}

	limit := queryInt(c, "limit", 20)
	offset := queryInt(c, "offset", 0)

	items, err := h.translationService.List(c.Request.Context(), operationID, limit, offset)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}
