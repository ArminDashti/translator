package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/armin/translator/internal/domain"
)

func (h *Handler) ListInstructions(c *gin.Context) {
	items, err := h.instructionService.List(c.Request.Context())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *Handler) GetInstruction(c *gin.Context) {
	key := c.Param("key")
	item, err := h.instructionService.Get(c.Request.Context(), key)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}

type updateInstructionRequest struct {
	Content string `json:"content" binding:"required"`
}

func (h *Handler) PutInstruction(c *gin.Context) {
	key := c.Param("key")
	var req updateInstructionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	item, err := h.instructionService.Update(c.Request.Context(), key, req.Content)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}
