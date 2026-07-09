package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/armin/translator/internal/domain"
	"github.com/armin/translator/internal/service"
)

func JWTAuth(authService *service.AuthService) gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, domain.APIError{
				Error: "missing or invalid authorization header",
				Code:  "UNAUTHORIZED",
			})
			return
		}

		token := strings.TrimPrefix(auth, "Bearer ")
		claims, err := authService.ValidateToken(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, domain.APIError{
				Error: "invalid or expired token",
				Code:  "UNAUTHORIZED",
			})
			return
		}

		c.Set("username", claims.Username)
		c.Set("user_id", claims.UserID)
		c.Next()
	}
}
