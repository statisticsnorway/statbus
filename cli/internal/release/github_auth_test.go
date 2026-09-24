package release

import (
	"bytes"
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func stubGH(t *testing.T, output string, success bool) {
	t.Helper()
	dir := t.TempDir()
	exit := "0"
	if !success {
		exit = "1"
	}
	script := "#!/bin/sh\nprintf '%s\\n' '" + output + "'\nexit " + exit + "\n"
	path := filepath.Join(dir, "gh")
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
}

func TestGitHubAuthPrecedenceAndFallback(t *testing.T) {
	t.Run("environment wins", func(t *testing.T) {
		t.Setenv("GITHUB_TOKEN", "env-token")
		stubGH(t, "cli-token", true)
		auth := GitHubAuth()
		if auth.Token != "env-token" || auth.Mode != GitHubAuthEnv {
			t.Fatalf("got %#v", auth)
		}
	})
	t.Run("gh auth fallback", func(t *testing.T) {
		t.Setenv("GITHUB_TOKEN", "")
		stubGH(t, "cli-token", true)
		auth := GitHubAuth()
		if auth.Token != "cli-token" || auth.Mode != GitHubAuthCLI {
			t.Fatalf("got %#v", auth)
		}
	})
	t.Run("anonymous", func(t *testing.T) {
		t.Setenv("GITHUB_TOKEN", "")
		stubGH(t, "", false)
		auth := GitHubAuth()
		if auth.Token != "" || auth.Mode != GitHubAuthAnonymous {
			t.Fatalf("got %#v", auth)
		}
	})
}

func TestGitHubGitEnvUsesExtraHeaderNotArgv(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "secret-token")
	env := GitHubGitEnv([]string{"HOME=/tmp/home"})
	joined := strings.Join(env, "\n")
	want := base64.StdEncoding.EncodeToString([]byte("x-access-token:secret-token"))
	if !strings.Contains(joined, "GIT_CONFIG_COUNT=2") ||
		!strings.Contains(joined, "GIT_CONFIG_VALUE_0=") ||
		!strings.Contains(joined, "GIT_CONFIG_VALUE_1=AUTHORIZATION: basic "+want) {
		t.Fatalf("missing encoded extraheader in %q", joined)
	}
}

func TestGitHubGitEnvResetsInheritedAuthorizationBeforeAddingItsOwn(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "secret-token")
	env := GitHubGitEnv([]string{
		"GIT_CONFIG_COUNT=1",
		"GIT_CONFIG_KEY_0=credential.helper",
		"GIT_CONFIG_VALUE_0=store",
	})
	joined := strings.Join(env, "\n")
	want := base64.StdEncoding.EncodeToString([]byte("x-access-token:secret-token"))
	for _, item := range []string{
		"GIT_CONFIG_COUNT=3",
		"GIT_CONFIG_KEY_1=http.https://github.com/.extraheader",
		"GIT_CONFIG_VALUE_1=",
		"GIT_CONFIG_KEY_2=http.https://github.com/.extraheader",
		"GIT_CONFIG_VALUE_2=AUTHORIZATION: basic " + want,
	} {
		if !strings.Contains(joined, item) {
			t.Fatalf("missing %q in %q", item, joined)
		}
	}
}

func TestAuthenticatedGitFailureRedactsCredentialsBeforeErrorsLogsAndDiagnostics(t *testing.T) {
	const token = "sentinel-token-MUST-NOT-LEAK"
	t.Setenv("GITHUB_TOKEN", token)
	dir := t.TempDir()
	encodedToken := base64.StdEncoding.EncodeToString([]byte(token))
	encodedCredential := base64.StdEncoding.EncodeToString([]byte("x-access-token:" + token))
	script := `#!/bin/sh
printf '%s\n' "$GITHUB_TOKEN" >&2
printf '%s\n' "` + encodedToken + `" >&2
printf '%s\n' "$GIT_CONFIG_VALUE_1" >&2
printf '%s\n' "Authorization: Bearer reflected-secret" >&2
exit 1
`
	if err := os.WriteFile(filepath.Join(dir, "git"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)

	_, _, err := migrationUpBlobHashInTag(t.TempDir(), "v2026.09.1-rc.99", 20260923000000)
	if err == nil {
		t.Fatal("expected authenticated git failure")
	}

	var userVisibleLog bytes.Buffer
	userVisibleLog.WriteString(err.Error())
	diagnosticPath := filepath.Join(t.TempDir(), "support-bundle-release-error.txt")
	if writeErr := os.WriteFile(diagnosticPath, userVisibleLog.Bytes(), 0o600); writeErr != nil {
		t.Fatal(writeErr)
	}
	diagnostic, readErr := os.ReadFile(diagnosticPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	for surface, content := range map[string]string{
		"returned error":            err.Error(),
		"user-visible log":          userVisibleLog.String(),
		"support bundle collection": string(diagnostic),
	} {
		for _, secret := range []string{token, encodedToken, encodedCredential, "reflected-secret"} {
			if strings.Contains(content, secret) {
				t.Fatalf("%s leaked %q in %q", surface, secret, content)
			}
		}
		if !strings.Contains(content, "[REDACTED]") {
			t.Fatalf("%s did not retain a redaction marker: %q", surface, content)
		}
	}
}
