package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func TestStartImageBasedDevelopmentSkipsBuild(t *testing.T) {
	t.Setenv("CADDY_DEPLOYMENT_MODE", "development")
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("CADDY_DEPLOYMENT_MODE=development\nVERSION=v2026.09.3\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if args := strings.Join(startComposeArgs("all", startBuildsFromSource(dir)), " "); strings.Contains(args, "--build") || !strings.Contains(args, "--no-build") {
		t.Fatalf("published image start must prohibit local builds: %s", args)
	}
}

func TestStartSourceDevelopmentBuilds(t *testing.T) {
	t.Setenv("CADDY_DEPLOYMENT_MODE", "development")
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("CADDY_DEPLOYMENT_MODE=development\nVERSION=local\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if args := strings.Join(startComposeArgs("all", startBuildsFromSource(dir)), " "); !strings.Contains(args, "--build") {
		t.Fatalf("source development start must build: %s", args)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("CADDY_DEPLOYMENT_MODE=development\nVERSION=v2026.09.2-3-g12345678\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if !startBuildsFromSource(dir) {
		t.Fatal("a source commit after a release tag must still build")
	}
}

func TestStartServicesRefusesWhileRecoveryFlockHeld(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(dir+"/.statbus", nil, 0o644); err != nil {
		t.Fatal(err)
	}
	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(oldWD) })

	owner, err := upgrade.AcquireInstallFlag(dir, "test:live-recovery")
	if err != nil {
		t.Fatal(err)
	}
	defer upgrade.ReleaseInstallFlag(owner)

	err = startServices("all", false)
	if err == nil || !strings.Contains(err.Error(), fmt.Sprintf("(process %d) is still running", os.Getpid())) {
		t.Fatalf("sb start while recovery flock held = %v, want plain holder PID", err)
	}
}

func TestRemoteRestoreUsesRecoveryLockAwareServiceStart(t *testing.T) {
	source, err := os.ReadFile(thisRepoFile(t, "cli/cmd/db.go"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	if strings.Contains(text, "docker compose start worker rest") {
		t.Fatal("remote restore bypasses the recovery flock with raw docker compose start")
	}
	if !strings.Contains(text, "./sb start all_except_app") || !strings.Contains(text, "./sb install for recovery diagnosis") {
		t.Fatal("remote restore must use the recovery-lock-aware start command and preserve refusal guidance")
	}
}
