package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/armin/translator/internal/domain"
	"github.com/armin/translator/internal/service"
)

func (h *Handler) Transform(c *gin.Context) {
	var req service.TransformRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	result, err := h.transformService.Transform(c.Request.Context(), req)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, result)
}

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

func (h *Handler) ListHistory(c *gin.Context) {
	sortBy := c.DefaultQuery("sort_by", "datetime")
	sortOrder := c.DefaultQuery("sort_order", "desc")
	limit := queryInt(c, "limit", 100)
	offset := queryInt(c, "offset", 0)

	items, err := h.historyService.List(c.Request.Context(), sortBy, sortOrder, limit, offset)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *Handler) GetHistory(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	item, err := h.historyService.Get(c.Request.Context(), id.String())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *Handler) DeleteHistory(c *gin.Context) {
	id, ok := parseUUIDParam(c, "id")
	if !ok {
		return
	}

	if err := h.historyService.Delete(c.Request.Context(), id.String()); err != nil {
		h.handleError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *Handler) GetStats(c *gin.Context) {
	stats, err := h.statsService.Get(c.Request.Context())
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, stats)
}
