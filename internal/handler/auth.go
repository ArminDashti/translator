package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/armin/translator/internal/domain"
)

type loginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *Handler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, domain.APIError{Error: err.Error(), Code: "VALIDATION_ERROR"})
		return
	}

	resp, err := h.authService.Login(c.Request.Context(), req.Username, req.Password)
	if err != nil {
		h.handleError(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}
