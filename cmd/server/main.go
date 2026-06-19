package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

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

	settingsRepo := repository.NewSettingsRepository(pool)
	modelRepo := repository.NewModelCatalogRepository(pool)
	operationRepo := repository.NewOperationCatalogRepository(pool)
	translationRepo := repository.NewTranslationRepository(pool)
	reviewRepo := repository.NewReviewRepository(pool)

	settingsService := service.NewSettingsService(settingsRepo, modelRepo)
	operationService := service.NewOperationService(operationRepo)
	instructionService := service.NewInstructionService(cfg.InstructionsDir)
	openRouter := service.NewOpenRouterClient(cfg.OpenRouterAPIKey, "")
	translationService := service.NewTranslationService(operationRepo, translationRepo, settingsService, instructionService, openRouter)
	reviewService := service.NewReviewService(reviewRepo, translationRepo)

	if err := instructionService.EnsureDefaults(
		[]string{"en_to_fa", "en_proofreading", "fa_to_en", "en_lexical_retrieval"},
		defaultInstructions(),
	); err != nil {
		log.Fatalf("instructions: %v", err)
	}

	h := handler.New(settingsService, operationService, translationService, reviewService, instructionService)

	router := gin.Default()
	router.GET("/api/v1/health", h.Health)

	api := router.Group("/api/v1")
	api.Use(middleware.Auth(cfg.APIToken))
	{
		api.GET("/operations", h.ListOperations)
		api.POST("/translate", h.Translate)
		api.GET("/translations", h.ListTranslations)
		api.GET("/translations/:id", h.GetTranslation)
		api.PATCH("/translations/:id", h.PatchTranslation)

		api.GET("/instructions/:operation_id", h.GetInstructions)
		api.PUT("/instructions/:operation_id", h.PutInstructions)

		api.GET("/settings", h.GetSettings)
		api.PATCH("/settings", h.PatchSettings)
		api.GET("/settings/models", h.ListModels)
		api.POST("/settings/models", h.CreateModel)
		api.PUT("/settings/models/:id", h.UpdateModel)
		api.DELETE("/settings/models/:id", h.DeleteModel)

		api.POST("/reviews", h.CreateReview)
		api.GET("/reviews", h.ListReviews)
		api.GET("/reviews/:id", h.GetReview)
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

func defaultInstructions() map[string]struct{ Fixed, User string } {
	jsonContract := `You must respond with ONLY valid JSON, no markdown fences:
{"candidate1":"...","candidate2":"...","candidate3":"..."}`

	return map[string]struct{ Fixed, User string }{
		"en_to_fa": {
			Fixed: jsonContract + "\n\nYou are a professional English-to-Persian translator. Provide three distinct, high-quality Persian translations.",
			User:  "Prioritize natural Persian phrasing and preserve the original meaning.",
		},
		"en_proofreading": {
			Fixed: jsonContract + "\n\nYou are an English proofreading specialist. Provide three improved versions of the input text.",
			User:  "Focus on grammar, clarity, and professional tone while preserving intent.",
		},
		"fa_to_en": {
			Fixed: jsonContract + "\n\nYou are a professional Persian-to-English translator. Provide three distinct, high-quality English translations.",
			User:  "Prioritize natural English phrasing and preserve the original meaning.",
		},
		"en_lexical_retrieval": {
			Fixed: jsonContract + "\n\nYou are an English lexical retrieval assistant. Given a semantic description, provide three candidate English words or short phrases.",
			User:  "Each candidate should be a distinct term that best matches the description.",
		},
	}
}
