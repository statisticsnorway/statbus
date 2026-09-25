package upgrade

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestOperatorCredentialsFallbackAndOverride(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("GITHUB_TOKEN=file-token\nSLACK_TOKEN=file-slack\nSEQ_API_KEY=file-seq\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"GITHUB_TOKEN", "SLACK_TOKEN", "SEQ_API_KEY"} {
		t.Setenv(key, "")
	}
	if err := loadOperatorCredentials(dir); err != nil {
		t.Fatal(err)
	}
	for key, want := range map[string]string{"GITHUB_TOKEN": "file-token", "SLACK_TOKEN": "file-slack", "SEQ_API_KEY": "file-seq"} {
		if got := os.Getenv(key); got != want {
			t.Errorf("%s fallback: got %q, want %q", key, got, want)
		}
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer file-token" {
			t.Errorf("request auth: got %q", got)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	req, err := githubRequest(http.MethodGet, server.URL)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	t.Setenv("GITHUB_TOKEN", "env-token")
	t.Setenv("SLACK_TOKEN", "env-slack")
	t.Setenv("SEQ_API_KEY", "env-seq")
	if err := loadOperatorCredentials(dir); err != nil {
		t.Fatal(err)
	}
	for key, want := range map[string]string{"GITHUB_TOKEN": "env-token", "SLACK_TOKEN": "env-slack", "SEQ_API_KEY": "env-seq"} {
		if got := os.Getenv(key); got != want {
			t.Errorf("%s override: got %q, want %q", key, got, want)
		}
	}
}
