package cmd

import (
	"os"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

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
	if err == nil || !strings.Contains(err.Error(), "./sb install") {
		t.Fatalf("sb start while recovery flock held = %v, want refusal with ./sb install guidance", err)
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
