package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/config"
)

func credentialInstallFixture(t *testing.T, legacy bool) string {
	t.Helper()
	dir := t.TempDir()
	root := filepath.Join("..", "..")
	example, err := os.ReadFile(filepath.Join(root, ".env.example"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.example"), example, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(dir, "caddy", "templates"), os.DirFS(filepath.Join(root, "caddy", "templates"))); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "ops", "maintenance"), 0755); err != nil {
		t.Fatal(err)
	}
	if legacy {
		if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("previous generation\n"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestInstallerFreshMisplacedSecretRejected_STATBUS361(t *testing.T) {
	for _, step := range []struct {
		name string
		run  func(string) error
	}{{"Credentials", runCreateCreds}, {"Settings", runGenerateEnv}} {
		t.Run(step.name, func(t *testing.T) {
			dir := credentialInstallFixture(t, false)
			cfg := filepath.Join(dir, ".env.config")
			original := "CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\nGITHUB_TOKEN=fresh\n"
			if err := os.WriteFile(cfg, []byte(original), 0600); err != nil {
				t.Fatal(err)
			}
			err := step.run(dir)
			if err == nil || !strings.Contains(err.Error(), "GITHUB_TOKEN in .env.config is a secret; move it to .env.credentials") || strings.Contains(err.Error(), "run ./sb install") {
				t.Fatalf("fresh install refusal: %v", err)
			}
			got, err := os.ReadFile(cfg)
			if err != nil || string(got) != original {
				t.Fatalf("fresh config altered: %q, %v", got, err)
			}
		})
	}
}

func TestInstallerRerunMigratesDuplicatesOnce_STATBUS361(t *testing.T) {
	dir := credentialInstallFixture(t, true)
	cfg := filepath.Join(dir, ".env.config")
	if err := os.WriteFile(cfg, []byte("CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\nGITHUB_TOKEN=old\nGITHUB_TOKEN=last\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := runCreateCreds(dir); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfg)
	if err != nil || strings.Contains(string(got), "GITHUB_TOKEN=") {
		t.Fatalf("legacy config retains token: %q, %v", got, err)
	}
	credsPath := filepath.Join(dir, ".env.credentials")
	creds, err := os.ReadFile(credsPath)
	if err != nil || !strings.Contains(string(creds), "GITHUB_TOKEN=last") {
		t.Fatalf("legacy credential missing: %q, %v", creds, err)
	}
	if err := runGenerateEnv(dir); err != nil {
		t.Fatal(err)
	}
	if err := runCreateCreds(dir); err != nil {
		t.Fatal(err)
	}
	again, err := os.ReadFile(credsPath)
	if err != nil || string(again) != string(creds) {
		t.Fatalf("rerun modified credentials: %q, %v", again, err)
	}
}

func TestStandaloneGenerateLegacyPointsToInstall_STATBUS361(t *testing.T) {
	dir := credentialInstallFixture(t, true)
	cfg := filepath.Join(dir, ".env.config")
	original := "GITHUB_TOKEN=legacy\n"
	if err := os.WriteFile(cfg, []byte(original), 0600); err != nil {
		t.Fatal(err)
	}
	err := config.GenerateInDir(dir, false)
	if err == nil || !strings.Contains(err.Error(), "run ./sb install") {
		t.Fatalf("standalone legacy guidance: %v", err)
	}
	got, readErr := os.ReadFile(cfg)
	if readErr != nil || string(got) != original {
		t.Fatalf("standalone migrated secret: %q, %v", got, readErr)
	}
}
