package service

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type InstructionService struct {
	baseDir string
}

func NewInstructionService(baseDir string) *InstructionService {
	return &InstructionService{baseDir: baseDir}
}

func (s *InstructionService) EnsureDefaults(slugs []string, defaults map[string]struct{ Fixed, User string }) error {
	for _, slug := range slugs {
		for _, layer := range []string{"fixed", "user"} {
			dir := filepath.Join(s.baseDir, layer)
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return fmt.Errorf("create instruction dir: %w", err)
			}
			path := filepath.Join(dir, slug+".md")
			if _, err := os.Stat(path); os.IsNotExist(err) {
				content := ""
				if layer == "fixed" {
					content = defaults[slug].Fixed
				} else {
					content = defaults[slug].User
				}
				if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
					return fmt.Errorf("write default instruction: %w", err)
				}
			}
		}
	}
	return nil
}

func (s *InstructionService) Get(slug string) (fixed, user string, err error) {
	fixedBytes, err := os.ReadFile(s.fixedPath(slug))
	if err != nil {
		return "", "", fmt.Errorf("read fixed instruction: %w", err)
	}
	userBytes, err := os.ReadFile(s.userPath(slug))
	if err != nil {
		return "", "", fmt.Errorf("read user instruction: %w", err)
	}
	return string(fixedBytes), string(userBytes), nil
}

func (s *InstructionService) BuildSystemPrompt(slug string) (string, error) {
	fixed, user, err := s.Get(slug)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(fixed) + "\n\n" + strings.TrimSpace(user), nil
}

func (s *InstructionService) Update(slug, layer, content string) error {
	var path string
	switch layer {
	case "fixed":
		path = s.fixedPath(slug)
	case "user":
		path = s.userPath(slug)
	default:
		return fmt.Errorf("invalid layer: %s", layer)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return fmt.Errorf("write instruction: %w", err)
	}
	return nil
}

func (s *InstructionService) fixedPath(slug string) string {
	return filepath.Join(s.baseDir, "fixed", slug+".md")
}

func (s *InstructionService) userPath(slug string) string {
	return filepath.Join(s.baseDir, "user", slug+".md")
}
