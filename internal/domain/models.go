package domain

import (
	"time"

	"github.com/google/uuid"
)

type LLMModel struct {
	ID           uuid.UUID `json:"id"`
	Slug         string    `json:"slug"`
	OpenRouterID string    `json:"openrouter_id"`
	DisplayName  string    `json:"display_name"`
	IsActive     bool      `json:"is_active"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type AppSettings struct {
	DefaultModelID *uuid.UUID `json:"default_model_id"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

type TranslationOperation struct {
	ID          uuid.UUID `json:"id"`
	Slug        string    `json:"slug"`
	DisplayName string    `json:"display_name"`
	Description *string   `json:"description,omitempty"`
	IsActive    bool      `json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`
}

type Translation struct {
	ID                uuid.UUID `json:"id"`
	OperationID       uuid.UUID `json:"operation_id"`
	OperationSlug     string    `json:"operation_slug,omitempty"`
	InputText         string    `json:"input_text"`
	ModelID           uuid.UUID `json:"model_id"`
	ModelSlug         string    `json:"model_slug,omitempty"`
	Candidate1        string    `json:"candidate1"`
	Candidate2        string    `json:"candidate2"`
	Candidate3        string    `json:"candidate3"`
	SelectedCandidate *int      `json:"selected_candidate"`
	CreatedAt         time.Time `json:"created_at"`
}

type Review struct {
	ID                uuid.UUID    `json:"id"`
	TranslationID     uuid.UUID    `json:"translation_id"`
	Rating            int          `json:"rating"`
	Comment           *string      `json:"comment,omitempty"`
	SelectedCandidate *int         `json:"selected_candidate,omitempty"`
	CreatedAt         time.Time    `json:"created_at"`
	Translation       *Translation `json:"translation,omitempty"`
}

type TranslationCandidates struct {
	Candidate1 string `json:"candidate1"`
	Candidate2 string `json:"candidate2"`
	Candidate3 string `json:"candidate3"`
}

type APIError struct {
	Error string `json:"error"`
	Code  string `json:"code"`
}

type InstructionLayers struct {
	Fixed string `json:"fixed"`
	User  string `json:"user"`
}
