package release

import (
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
	if !strings.Contains(joined, "GIT_CONFIG_VALUE_0=AUTHORIZATION: basic "+want) {
		t.Fatalf("missing encoded extraheader in %q", joined)
	}
}
