package middleware

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/armin/translator/internal/domain"
)

func Auth(apiToken string) gin.HandlerFunc {
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
		if subtle.ConstantTimeCompare([]byte(token), []byte(apiToken)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, domain.APIError{
				Error: "invalid token",
				Code:  "UNAUTHORIZED",
			})
			return
		}

		c.Next()
	}
}
