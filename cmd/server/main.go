package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/armin/translator/internal/config"
	"github.com/armin/translator/internal/db"
	"github.com/armin/translator/internal/handler"
	"github.com/armin/translator/internal/middleware"
	"github.com/armin/translator/internal/repository"
	"github.com/armin/translator/internal/service"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	if err := db.RunMigrations(cfg.DatabaseURL); err != nil {
		log.Fatalf("migrations: %v", err)
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer pool.Close()

	userRepo := repository.NewUserRepository(pool)
	settingsRepo := repository.NewSettingsRepository(pool)
	historyRepo := repository.NewHistoryRepository(pool)
	instructionRepo := repository.NewInstructionRepository(pool)

	authService := service.NewAuthService(userRepo, cfg.JWTSecret)
	settingsService := service.NewSettingsService(settingsRepo)
	instructionService := service.NewInstructionService(instructionRepo)
	openRouter := service.NewOpenRouterClient("")
	transformService := service.NewTransformService(historyRepo, settingsService, instructionService, openRouter)
	historyService := service.NewHistoryService(historyRepo)
	statsService := service.NewStatsService(historyRepo)

	if err := authService.EnsureDefaultUser(ctx, cfg.DefaultUsername, cfg.DefaultPassword); err != nil {
		log.Fatalf("default user: %v", err)
	}
	if err := instructionService.EnsureDefaults(ctx); err != nil {
		log.Fatalf("instructions: %v", err)
	}

	h := handler.New(authService, transformService, historyService, statsService, settingsService, instructionService)

	router := gin.Default()
	router.Use(cors.New(cors.Config{
		AllowOrigins: []string{
			"http://localhost:5173",
			"http://127.0.0.1:5173",
			"http://localhost:8082",
			"http://127.0.0.1:8082",
		},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Authorization", "Content-Type"},
		AllowCredentials: true,
	}))

	router.GET("/api/v1/health", h.Health)
	router.POST("/api/v1/auth/login", h.Login)

	api := router.Group("/api/v1")
	api.Use(middleware.JWTAuth(authService))
	{
		api.POST("/transform", h.Transform)
		api.GET("/history", h.ListHistory)
		api.GET("/history/:id", h.GetHistory)
		api.DELETE("/history/:id", h.DeleteHistory)
		api.GET("/stats", h.GetStats)

		api.GET("/instructions", h.ListInstructions)
		api.GET("/instructions/:key", h.GetInstruction)
		api.PUT("/instructions/:key", h.PutInstruction)

		api.GET("/settings", h.GetSettings)
		api.PATCH("/settings", h.PatchSettings)
		api.DELETE("/settings/data", h.ClearData)
	}

	if _, err := os.Stat(cfg.StaticDir); err == nil {
		router.Static("/assets", cfg.StaticDir+"/assets")
		router.NoRoute(func(c *gin.Context) {
			if len(c.Request.URL.Path) >= 4 && c.Request.URL.Path[:4] == "/api" {
				c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
				return
			}
			c.File(cfg.StaticDir + "/index.html")
		})
	}

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: router,
	}

	go func() {
		log.Printf("server listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("shutdown: %v", err)
	}
}
