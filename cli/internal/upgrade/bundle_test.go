package upgrade

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestWriteBundleSections_Composition drives WriteBundleSections with a
// fixture upgrade row and a fixture log file, then asserts that all
// canonical section markers are present in the output.
func TestWriteBundleSections_Composition(t *testing.T) {
	dir := t.TempDir()

	// Fixture log file
	logPath := filepath.Join(dir, "upgrade-abc123.log")
	if err := os.WriteFile(logPath, []byte("step 1: started\nstep 2: finished\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	// Fixture upgrade row — minimal valid JSON
	rowJSON := `{"id":42,"commit_sha":"abc123def456","state":"failed","version":"v2026.04.0-rc.9"}`

	var buf bytes.Buffer
	WriteBundleSections(context.Background(), &buf, dir, 42, rowJSON, logPath)
	output := buf.String()

	wantSections := []string{
		"=== bundle for upgrade id=42 commit=abc123def456 state=failed ===",
		"=== generated ",
		"=== upgrade row (key=value) ===",
		"=== log tail (last 500 lines from upgrade-abc123.log) ===",
		"=== docker compose ps ===",
		// journalctl section is skipped on hosts without journalctl — don't assert it
		"=== git log -20 ===",
		"=== redacted env ===",
	}

	for _, want := range wantSections {
		if !strings.Contains(output, want) {
			t.Errorf("expected section marker %q not found in bundle output", want)
		}
	}

	// Log content should appear in the log-tail section
	if !strings.Contains(output, "step 1: started") {
		t.Error("expected log content in bundle output")
	}
	if !strings.Contains(output, "step 2: finished") {
		t.Error("expected log content in bundle output")
	}
}

// TestWriteBundleSections_RedactedEnv verifies that the env section redacts
// keys matching the secret pattern and preserves non-secret keys.
func TestWriteBundleSections_RedactedEnv(t *testing.T) {
	dir := t.TempDir()

	// Write a .env file with both secret and plain keys
	envContent := "SITE_DOMAIN=example.com\n" +
		"POSTGRES_APP_PASSWORD=supersecret\n" +
		"SLACK_WEBHOOK=https://hooks.slack.com/abc\n" +
		"JWT_SECRET=my-jwt-secret\n" +
		"PRIVATE_KEY=-----BEGIN...\n" +
		"API_KEY=key-123\n" +
		"UPGRADE_CHANNEL=prerelease\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(envContent), 0o644); err != nil {
		t.Fatal(err)
	}

	// No log file needed — use /dev/null equivalent
	logPath := filepath.Join(dir, "no.log")

	var buf bytes.Buffer
	WriteBundleSections(context.Background(), &buf, dir, 1, `{"id":1,"state":"failed"}`, logPath)
	output := buf.String()

	// Secret keys must have their values replaced
	secretKeys := []string{
		"POSTGRES_APP_PASSWORD",
		"SLACK_WEBHOOK",
		"JWT_SECRET",
		"PRIVATE_KEY",
		"API_KEY",
	}
	for _, key := range secretKeys {
		// The key itself should appear
		if !strings.Contains(output, key+"=") {
			t.Errorf("expected key %q to appear in env section", key)
		}
		// But its original value must not appear
	}

	// Actual secret values must NOT appear
	forbidden := []string{"supersecret", "my-jwt-secret", "-----BEGIN", "key-123"}
	for _, val := range forbidden {
		if strings.Contains(output, val) {
			t.Errorf("secret value %q leaked into bundle output", val)
		}
	}
	// Redaction placeholder must appear
	if !strings.Contains(output, "***REDACTED***") {
		t.Error("expected ***REDACTED*** placeholder in env section")
	}

	// Non-secret keys must appear with their real values
	if !strings.Contains(output, "SITE_DOMAIN=example.com") {
		t.Error("expected non-secret SITE_DOMAIN=example.com in env section")
	}
	if !strings.Contains(output, "UPGRADE_CHANNEL=prerelease") {
		t.Error("expected non-secret UPGRADE_CHANNEL=prerelease in env section")
	}
}

// TestWriteBundleSections_InlineLogRedaction verifies that inline secrets in
// log lines are scrubbed by bundleInlineSecretRe.
func TestWriteBundleSections_InlineLogRedaction(t *testing.T) {
	dir := t.TempDir()

	logPath := filepath.Join(dir, "upgrade.log")
	logContent := "connecting with password=hunter2\n" +
		"using token=ghp_abc123def456\n" +
		"secret=topsecret in request\n" +
		"normal log line\n"
	if err := os.WriteFile(logPath, []byte(logContent), 0o644); err != nil {
		t.Fatal(err)
	}

	var buf bytes.Buffer
	WriteBundleSections(context.Background(), &buf, dir, 1, `{"id":1,"state":"failed"}`, logPath)
	output := buf.String()

	// Inline secret values must not appear verbatim
	forbidden := []string{"hunter2", "ghp_abc123def456", "topsecret"}
	for _, val := range forbidden {
		if strings.Contains(output, val) {
			t.Errorf("inline secret %q leaked through log redaction", val)
		}
	}

	// Normal log line should be untouched
	if !strings.Contains(output, "normal log line") {
		t.Error("expected normal log line to be preserved")
	}

	// Redacted form: key= prefix preserved, value replaced
	if !strings.Contains(output, "password=***REDACTED***") {
		t.Error("expected password= to be redacted in log section")
	}
	if !strings.Contains(output, "token=***REDACTED***") {
		t.Error("expected token= to be redacted in log section")
	}
}

// TestBundleEnvSecretKeyRe_Coverage enumerates all pattern variants the
// bundleEnvSecretKeyRe must catch — keeps the regex honest if someone edits it.
func TestBundleEnvSecretKeyRe_Coverage(t *testing.T) {
	cases := []struct {
		key   string
		match bool
	}{
		{"POSTGRES_APP_PASSWORD", true},
		{"password", true},
		{"JWT_SECRET", true},
		{"MY_SECRET_KEY", true},
		{"SLACK_WEBHOOK", true},
		{"PRIVATE_KEY", true},
		{"PRIVATEKEY", true},
		{"API_KEY", true},
		{"APIKEY", true},
		{"GITHUB_TOKEN", true},
		{"token", true},
		// Non-secrets
		{"SITE_DOMAIN", false},
		{"UPGRADE_CHANNEL", false},
		{"DEPLOYMENT_SLOT_CODE", false},
		{"APP_PORT", false},
	}
	for _, c := range cases {
		got := bundleEnvSecretKeyRe.MatchString(c.key)
		if got != c.match {
			t.Errorf("bundleEnvSecretKeyRe.MatchString(%q) = %v, want %v", c.key, got, c.match)
		}
	}
}
