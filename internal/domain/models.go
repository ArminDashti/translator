package domain

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID           uuid.UUID `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

type AppSettings struct {
	OpenRouterAPIKey string    `json:"openrouter_api_key"`
	ModelName        string    `json:"model_name"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type Instruction struct {
	Key       string    `json:"key"`
	Content   string    `json:"content"`
	UpdatedAt time.Time `json:"updated_at"`
}

type HistoryType string

const (
	HistoryTypeSimplify HistoryType = "simplify"
	HistoryTypeEnFa     HistoryType = "en_fa"
	HistoryTypeFaEn     HistoryType = "fa_en"
	HistoryTypeTermEn   HistoryType = "term_en"
	HistoryTypeTermFa   HistoryType = "term_fa"
	HistoryTypeRefine   HistoryType = "refine"
	HistoryTypeSymptoms HistoryType = "symptoms"
)

func (t HistoryType) DisplayName() string {
	switch t {
	case HistoryTypeSimplify:
		return "Simplify"
	case HistoryTypeEnFa:
		return "EN-FA"
	case HistoryTypeFaEn:
		return "FA-EN"
	case HistoryTypeTermEn:
		return "Term EN"
	case HistoryTypeTermFa:
		return "Term FA"
	case HistoryTypeRefine:
		return "Refine"
	case HistoryTypeSymptoms:
		return "Symptoms"
	default:
		return string(t)
	}
}

type HistoryRecord struct {
	ID             uuid.UUID       `json:"id"`
	Type           HistoryType     `json:"type"`
	TypeDisplay    string          `json:"type_display"`
	InputText      string          `json:"input_text"`
	ResultText     string          `json:"result_text"`
	Model          string          `json:"model"`
	InstructionKey string          `json:"instruction_key"`
	Metadata       json.RawMessage `json:"metadata,omitempty"`
	CreatedAt      time.Time       `json:"created_at"`
	FormattedDate  string          `json:"formatted_date"`
}

type StatsBucket struct {
	Simplify  int `json:"simplify"`
	EnFa      int `json:"en_fa"`
	FaEn      int `json:"fa_en"`
	Term      int `json:"term"`
	Refine    int `json:"refine"`
	Symptoms  int `json:"symptoms"`
	Total     int `json:"total"`
}

type StatsResponse struct {
	Today     StatsBucket `json:"today"`
	Yesterday StatsBucket `json:"yesterday"`
	Week      StatsBucket `json:"week"`
	Month     StatsBucket `json:"month"`
	AllTime   StatsBucket `json:"all_time"`
}

type TransformResult struct {
	ID             uuid.UUID   `json:"id"`
	Type           HistoryType `json:"type"`
	TypeDisplay    string      `json:"type_display"`
	InputText      string      `json:"input_text"`
	ResultText     string      `json:"result_text"`
	Model          string      `json:"model"`
	InstructionKey string      `json:"instruction_key"`
	CreatedAt      time.Time   `json:"created_at"`
	FormattedDate  string      `json:"formatted_date"`
}

type APIError struct {
	Error string `json:"error"`
	Code  string `json:"code"`
}

type LoginResponse struct {
	Token    string `json:"token"`
	Username string `json:"username"`
}

var InstructionKeys = []string{
	"en-to-fa-general",
	"en-to-fa-movie",
	"en-to-fa-formal",
	"en-to-fa-scientific",
	"en-to-fa-music",
	"fa-to-en-general",
	"fa-to-en-formal",
	"fa-to-en-scientific",
	"simplify-en",
	"refine-to-everyday",
	"refine-to-formal",
	"refine-to-slang",
	"symptoms",
	"term-for-everyday",
	"term-for-formal",
	"term-for-slang",
}

func FormatDateTime(t time.Time) string {
	return t.Format("2006:01:02 15:04")
}
