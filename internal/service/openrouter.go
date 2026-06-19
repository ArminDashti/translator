package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/armin/translator/internal/domain"
)

const defaultOpenRouterURL = "https://openrouter.ai/api/v1/chat/completions"

type OpenRouterClient struct {
	apiKey  string
	baseURL string
	client  *http.Client
}

func NewOpenRouterClient(apiKey, baseURL string) *OpenRouterClient {
	if baseURL == "" {
		baseURL = defaultOpenRouterURL
	}
	return &OpenRouterClient{
		apiKey:  apiKey,
		baseURL: baseURL,
		client:  &http.Client{Timeout: 120 * time.Second},
	}
}

type chatRequest struct {
	Model          string          `json:"model"`
	Messages       []chatMessage   `json:"messages"`
	ResponseFormat *responseFormat `json:"response_format,omitempty"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type responseFormat struct {
	Type string `json:"type"`
}

type chatResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

func (c *OpenRouterClient) Complete(ctx context.Context, model, systemPrompt, userText string) (domain.TranslationCandidates, error) {
	candidates, err := c.completeOnce(ctx, model, systemPrompt, userText, true)
	if err == nil {
		return candidates, nil
	}

	candidates, retryErr := c.completeOnce(ctx, model, systemPrompt, userText, false)
	if retryErr != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("%w; retry failed: %v", err, retryErr)
	}
	return candidates, nil
}

func (c *OpenRouterClient) completeOnce(ctx context.Context, model, systemPrompt, userText string, useJSONFormat bool) (domain.TranslationCandidates, error) {
	reqBody := chatRequest{
		Model: model,
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userText},
		},
	}
	if useJSONFormat {
		reqBody.ResponseFormat = &responseFormat{Type: "json_object"}
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewReader(body))
	if err != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("openrouter request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return domain.TranslationCandidates{}, fmt.Errorf("openrouter status %d: %s", resp.StatusCode, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("unmarshal response: %w", err)
	}
	if chatResp.Error != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("openrouter error: %s", chatResp.Error.Message)
	}
	if len(chatResp.Choices) == 0 {
		return domain.TranslationCandidates{}, fmt.Errorf("openrouter returned no choices")
	}

	content := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	var candidates domain.TranslationCandidates
	if err := json.Unmarshal([]byte(content), &candidates); err != nil {
		return domain.TranslationCandidates{}, fmt.Errorf("parse candidates json: %w", err)
	}
	if candidates.Candidate1 == "" || candidates.Candidate2 == "" || candidates.Candidate3 == "" {
		return domain.TranslationCandidates{}, fmt.Errorf("incomplete candidates in response")
	}
	return candidates, nil
}
