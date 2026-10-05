package upgrade

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	statbusconfig "github.com/statisticsnorway/statbus/cli/internal/config"
)

func prepareLegacyConfigFixture(t *testing.T) (string, []byte, []byte) {
	t.Helper()
	dir := t.TempDir()
	fixtureDir := filepath.Join("..", "config", "testdata", "legacy-config", "v2026.09.2")
	for _, name := range []string{".env.config", ".env.credentials"} {
		contents, err := os.ReadFile(filepath.Join(fixtureDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, name), contents, 0600); err != nil {
			t.Fatal(err)
		}
	}
	repoRoot := filepath.Join("..", "..", "..")
	example, err := os.ReadFile(filepath.Join(repoRoot, ".env.example"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.example"), example, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(dir, "caddy", "templates"), os.DirFS(filepath.Join(repoRoot, "caddy", "templates"))); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "ops", "maintenance"), 0755); err != nil {
		t.Fatal(err)
	}
	configBefore, err := os.ReadFile(filepath.Join(dir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	credentialsBefore, err := os.ReadFile(filepath.Join(dir, ".env.credentials"))
	if err != nil {
		t.Fatal(err)
	}
	return dir, configBefore, credentialsBefore
}

func TestOperatorConfigSnapshotRestoresLegacyPlacementAfterTargetMigration(t *testing.T) {
	projDir, configBefore, credentialsBefore := prepareLegacyConfigFixture(t)
	backupPath := filepath.Join(t.TempDir(), backupActiveName)
	if err := os.Mkdir(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	if err := statbusconfig.GenerateForInstallInDir(projDir, false); err != nil {
		t.Fatal(err)
	}
	migratedConfig, err := os.ReadFile(filepath.Join(projDir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(migratedConfig), "SLACK_TOKEN=fixture-slack_token") || strings.Contains(string(migratedConfig), "SEQ_API_KEY=fixture-seq_api_key") {
		t.Fatalf("target migration did not move legacy tokens: %s", migratedConfig)
	}
	if err := restoreOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	assertFileBytes(t, filepath.Join(projDir, ".env.config"), configBefore)
	assertFileBytes(t, filepath.Join(projDir, ".env.credentials"), credentialsBefore)
	credentialsInfo, err := os.Stat(filepath.Join(projDir, ".env.credentials"))
	if err != nil {
		t.Fatal(err)
	}
	if got := credentialsInfo.Mode().Perm(); got != 0600 {
		t.Fatalf("credentials mode = %o, want 600", got)
	}
}

func TestOperatorConfigSnapshotRestoresAbsentFiles(t *testing.T) {
	projDir := t.TempDir()
	backupPath := filepath.Join(t.TempDir(), backupActiveName)
	if err := os.Mkdir(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".env.config", ".env.credentials"} {
		if err := os.WriteFile(filepath.Join(projDir, name), []byte("target-era\n"), 0644); err != nil {
			t.Fatal(err)
		}
	}
	if err := restoreOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".env.config", ".env.credentials"} {
		if _, err := os.Stat(filepath.Join(projDir, name)); !os.IsNotExist(err) {
			t.Fatalf("%s exists after absence restore: %v", name, err)
		}
	}
}

func TestForwardCompletionKeepsMigratedConfig(t *testing.T) {
	projDir, configBefore, _ := prepareLegacyConfigFixture(t)
	backupPath := filepath.Join(t.TempDir(), backupActiveName)
	if err := os.Mkdir(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	if err := statbusconfig.GenerateForInstallInDir(projDir, false); err != nil {
		t.Fatal(err)
	}
	configAfter, err := os.ReadFile(filepath.Join(projDir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(configAfter, configBefore) {
		t.Fatal("forward completion restored the legacy config instead of keeping migrated placement")
	}
	if strings.Contains(string(configAfter), "SLACK_TOKEN=fixture-slack_token") || strings.Contains(string(configAfter), "SEQ_API_KEY=fixture-seq_api_key") {
		t.Fatalf("forward completion retained legacy token placement: %s", configAfter)
	}
	if _, err := os.Stat(operatorConfigSnapshotPath(backupPath)); err != nil {
		t.Fatalf("forward completion must leave the snapshot with its database backup lifecycle: %v", err)
	}
}

func TestNewSnapshotReplacesStaleOperatorConfig(t *testing.T) {
	backupPath := filepath.Join(t.TempDir(), backupSyncingName)
	if err := os.Mkdir(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	staleDir := operatorConfigSnapshotPath(backupPath)
	if err := os.Mkdir(staleDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staleDir, ".env.credentials"), []byte("SLACK_TOKEN=stale\n"), 0600); err != nil {
		t.Fatal(err)
	}
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.config"), []byte("SITE_DOMAIN=fresh.example\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(staleDir, ".env.credentials")); !os.IsNotExist(err) {
		t.Fatalf("stale credentials survived replacement: %v", err)
	}
	if err := restoreOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	assertFileBytes(t, filepath.Join(projDir, ".env.config"), []byte("SITE_DOMAIN=fresh.example\n"))
}

func assertFileBytes(t *testing.T, path string, want []byte) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("%s changed byte-exact contents\ngot:  %q\nwant: %q", path, got, want)
	}
}
