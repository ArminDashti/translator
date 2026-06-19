package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/armin/translator/internal/domain"
)

func (h *Handler) GetInstructions(c *gin.Context) {
	operationID, ok := parseUUIDParam(c, "operation_id")
	if !ok {
		return
	}

	operation, err := h.operationService.Get(c.Request.Context(), operationID)
	if err != nil {
		h.handleError(c, err)
		return
	}

	fixed, user, err := h.instructionService.Get(operation.Slug)
	if err != nil {
		h.handleError(c, err)
		return
	}

	c.JSON(http.StatusOK, domain.InstructionLayers{Fixed: fixed, User: user})
}

type updateInstructionRequest struct {
	Layer   string `json:"layer" binding:"required,oneof=fixed user"`
	Content string `json:"content" binding:"required"`
}

func (h *Handler) PutInstructions(c *gin.Context) {
	operationID, ok := parseUUIDParam(c, "operation_id")
	if !ok {
		return
	}

	operation, err := h.operationService.Get(c.Request.Context(), operationID)
	if err != nil {
		h.handleError(c, err)
		return
	}

	var req updateInstructionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	if err := h.instructionService.Update(operation.Slug, req.Layer, req.Content); err != nil {
		h.handleError(c, err)
		return
	}

	fixed, user, err := h.instructionService.Get(operation.Slug)
	if err != nil {
		h.handleError(c, err)
		return
	}

	c.JSON(http.StatusOK, domain.InstructionLayers{Fixed: fixed, User: user})
}

type createReviewRequest struct {
	TranslationID     uuid.UUID `json:"translation_id" binding:"required"`
	Rating            int       `json:"rating" binding:"required,min=1,max=5"`
	Comment           *string   `json:"comment"`
	SelectedCandidate *int      `json:"selected_candidate" binding:"omitempty,min=1,max=3"`
}

func (h *Handler) CreateReview(c *gin.Context) {
	var req createReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	review, err := h.reviewService.Create(c.Request.Context(), req.TranslationID, req.Rating, req.Comment, req.SelectedCandidate)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, review)
}

func (h *Handler) GetReview(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	review, err := h.reviewService.Get(c.Request.Context(), id)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, review)
}

func (h *Handler) ListReviews(c *gin.Context) {
	var translationID *uuid.UUID
	if tid := c.Query("translation_id"); tid != "" {
		id, err := uuid.Parse(tid)
		if err != nil {
			c.JSON(http.StatusBadRequest, domain.APIError{Error: "invalid translation_id", Code: "INVALID_ID"})
			return
		}
		translationID = &id
	}

	limit := queryInt(c, "limit", 20)
	offset := queryInt(c, "offset", 0)

	reviews, err := h.reviewService.List(c.Request.Context(), translationID, limit, offset)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, reviews)
}
