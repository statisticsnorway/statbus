package livedbtest

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFixtureGenerationMigratesCopiedLegacySecrets_STATBUS446(t *testing.T) {
	source, project := t.TempDir(), t.TempDir()
	originals := map[string][]byte{
		".env.config":      []byte("# synthetic legacy checkout\nCADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\nSLACK_TOKEN=synthetic-446-slack\n"),
		".env.credentials": []byte("# synthetic existing credentials\nGITHUB_TOKEN=synthetic-446-github\n"),
	}
	for name, contents := range originals {
		if err := os.WriteFile(filepath.Join(source, name), contents, 0600); err != nil {
			t.Fatal(err)
		}
		if err := copyFile(filepath.Join(source, name), filepath.Join(project, name), 0600); err != nil {
			t.Fatal(err)
		}
	}
	root, err := findProjectRoot()
	if err != nil {
		t.Fatal(err)
	}
	if err := copyFile(filepath.Join(root, ".env.example"), filepath.Join(project, ".env.example"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(project, "caddy", "templates"), os.DirFS(filepath.Join(root, "caddy", "templates"))); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(project, "ops", "maintenance"), 0755); err != nil {
		t.Fatal(err)
	}
	commit, err := run(root, "git", "rev-parse", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if out, err := run(filepath.Join(root, "cli"), "go", "build", "-ldflags", "-X github.com/statisticsnorway/statbus/cli/cmd.commit="+commit, "-o", filepath.Join(project, "sb"), "."); err != nil {
		t.Fatalf("build fixture sb: %v: %s", err, out)
	}
	t.Setenv("HOME", t.TempDir())
	out, generateErr := generateFixtureConfig(project)
	// Check preservation even when strict baseline generation refuses.
	for name, before := range originals {
		after, err := os.ReadFile(filepath.Join(source, name))
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(before, after) {
			t.Errorf("source %s changed", name)
		}
	}
	if generateErr != nil {
		t.Fatalf("generate copied fixture config: %v: %s", generateErr, out)
	}
	config, err := os.ReadFile(filepath.Join(project, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(config), "SLACK_TOKEN=") {
		t.Fatal("legacy secret remains in destination config")
	}
	credentials, err := os.ReadFile(filepath.Join(project, ".env.credentials"))
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{"SLACK_TOKEN=synthetic-446-slack", "GITHUB_TOKEN=synthetic-446-github"} {
		if !strings.Contains(string(credentials), expected) {
			t.Errorf("destination credentials missing %s", expected)
		}
	}
	if _, err := os.Stat(filepath.Join(project, ".env")); err != nil {
		t.Fatalf("generated environment missing: %v", err)
	}
}
