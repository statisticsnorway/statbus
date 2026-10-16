package cmd

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// STATBUS-392: ./sb restart follows the same rule as ./sb start. A release
// installation (VERSION is a release tag) uses the published images, even in
// development mode. Only a source checkout builds.
func TestRestartUpArgsFollowStartBuildRule_STATBUS392(t *testing.T) {
	t.Setenv("CADDY_DEPLOYMENT_MODE", "development")
	for _, c := range []struct {
		version, profile string
		want             []string
	}{
		{"v2026.10.2", "all", []string{"--profile", "all", "-d", "--wait", "--wait-timeout", "120", "--no-build"}},
		{"v2026.10.2", "app", []string{"-d", "--wait", "--wait-timeout", "120", "--no-build", "app"}},
		{"local", "all", []string{"--profile", "all", "-d", "--wait", "--wait-timeout", "120", "--build"}},
		{"v2026.10.2-3-g12345678", "app", []string{"-d", "--wait", "--wait-timeout", "120", "--build", "app"}},
	} {
		dir := t.TempDir()
		env := "CADDY_DEPLOYMENT_MODE=development\nVERSION=" + c.version + "\n"
		if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0o600); err != nil {
			t.Fatal(err)
		}
		if got := restartUpArgs(dir, c.profile); !reflect.DeepEqual(got, c.want) {
			t.Errorf("VERSION=%s profile=%s: restartUpArgs = %q, want %q", c.version, c.profile, got, c.want)
		}
	}
}
