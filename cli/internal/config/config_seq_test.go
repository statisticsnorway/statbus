package config

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-361 follow-up: a fresh install must still satisfy the app service's
// :?-required SEQ_API_KEY (docker-compose.app.yml) without the operator ever
// placing a secret in .env.config. The value is a generated placeholder living
// in .env.credentials; an operator-supplied credential wins.
func TestSeqApiKeyPlaceholderGenerated_STATBUS361(t *testing.T) {
	dir := t.TempDir()
	creds, err := loadOrGenerateCredentials(dir, false)
	if err != nil {
		t.Fatalf("loadOrGenerateCredentials: %v", err)
	}
	if creds.SeqAPIKey == "" {
		t.Fatal("fresh credentials must include a placeholder SEQ_API_KEY; an empty value breaks docker compose's :? requirement")
	}
	// Supplied credential wins over the placeholder.
	if err := os.WriteFile(dir+"/.env.credentials", []byte("SEQ_API_KEY=operator-seq\n"), 0600); err != nil {
		t.Fatal(err)
	}
	creds2, err := loadOrGenerateCredentials(dir, false)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if creds2.SeqAPIKey != "operator-seq" {
		t.Fatalf("operator SEQ_API_KEY must win, got %q", creds2.SeqAPIKey)
	}
	if strings.Contains(creds2.SeqAPIKey, "secret_seq_api_key") {
		t.Fatal("placeholder leaked over operator value")
	}
}
