package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-584: moving secrets out of .env.config is config maintenance with
// one implementation, config.MigrateSecrets, behind ./sb config migrate. The
// hidden --migrate-legacy-secrets flag stays only for an upgrader from an
// earlier release, which calls the newly installed ./sb with it mid-upgrade
// (STATBUS-361: a strict refusal there crash-loops the service).
func TestConfigMigrateIsTheCommandAndTheOldFlagIsHidden(t *testing.T) {
	found, _, err := rootCmd.Find([]string{"config", "migrate"})
	if err != nil || found.Name() != "migrate" {
		t.Fatalf("./sb config migrate not found: %v", err)
	}
	f := configGenerateCmd.Flags().Lookup("migrate-legacy-secrets")
	if f == nil {
		t.Fatal("config generate must still accept --migrate-legacy-secrets from an earlier upgrader")
	}
	if !f.Hidden || f.DefValue != "false" {
		t.Fatalf("--migrate-legacy-secrets must be hidden and off by default (hidden=%v default=%s)", f.Hidden, f.DefValue)
	}
}

// Every ./sb config generate the upgrader runs on the target tree is preceded
// by config.MigrateSecrets in the same function, and none passes the old flag:
// the upgrader moves secrets with the same code as ./sb config migrate.
func TestUpgradeServiceMovesSecretsBeforeEachTargetRegeneration(t *testing.T) {
	src, err := os.ReadFile(filepath.Join(thisRepoFile(t, "cli/internal/upgrade"), "service.go"))
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(src), "\n")
	targetSites := 0
	for i, line := range lines {
		if !strings.Contains(line, `"./sb", "config", "generate"`) {
			continue
		}
		if strings.Contains(line, "--migrate-legacy-secrets") {
			t.Errorf("service.go:%d passes the old flag; move secrets with config.MigrateSecrets instead", i+1)
		}
		window := line
		if i > 0 {
			window = lines[i-1] + window
		}
		if strings.Contains(window, "park-config-generate") || strings.Contains(window, "preswap-terminal-config-generate") {
			continue // the source tree's own binary; it predates the refusal
		}
		targetSites++
		migrated := false
		for j := i - 1; j >= 0 && j >= i-12; j-- {
			if strings.Contains(lines[j], "config.MigrateSecrets(") {
				migrated = true
				break
			}
		}
		if !migrated {
			t.Errorf("service.go:%d regenerates config without config.MigrateSecrets just before it", i+1)
		}
	}
	if targetSites < 2 {
		t.Fatalf("service.go: %d target config-generate sites, want >=2 (recovery boot + post-swap target)", targetSites)
	}
	_ = upgrade.ErrCommandTimeout // keep the import honest
}
