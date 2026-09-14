package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/installinput"
)

func unattendedFixture(t *testing.T) (string, string) {
	t.Helper()
	oldTrust := trustGitHubUser
	trustGitHubUser = ""
	t.Cleanup(func() { trustGitHubUser = oldTrust })
	old := nonInteractive
	nonInteractive = true
	t.Cleanup(func() { nonInteractive = old })
	t.Setenv(installinput.EnvConfig, "")
	t.Setenv(installinput.UsersFile, "")
	dir := t.TempDir()
	content := installinput.Ask(func(_ string, fallback string) string { return fallback })
	return dir, content
}

func TestUnattendedConfigImport(t *testing.T) {
	dir, content := unattendedFixture(t)
	input := filepath.Join(t.TempDir(), "input.env")
	if err := os.WriteFile(input, []byte(content+"TRUST_GITHUB_USER=jhf\n"), 0600); err != nil {
		t.Fatal(err)
	}
	users := filepath.Join(t.TempDir(), "users.yml")
	if err := os.WriteFile(users, []byte("users fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(installinput.EnvConfig, input)
	t.Setenv(installinput.UsersFile, users)
	if err := validateFreshInstallInput(dir, false); err != nil {
		t.Fatal(err)
	}
	if err := runCreateConfig(dir); err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]string{".env.config": content + "DEPLOYMENT_SLOT_PORT_OFFSET=1\n", ".users.yml": "users fixture"} {
		path := filepath.Join(dir, name)
		got, err := os.ReadFile(path)
		if err != nil || string(got) != want {
			t.Fatalf("%s: %q %v", name, got, err)
		}
		st, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if st.Mode().Perm() != 0600 {
			t.Fatalf("%s mode %v", name, st.Mode())
		}
	}
}

func TestUnattendedConfigFailFast(t *testing.T) {
	dir, content := unattendedFixture(t)
	err := validateFreshInstallInput(dir, false)
	if err == nil || !strings.Contains(err.Error(), installinput.Requirement()) {
		t.Fatalf("no env: %v", err)
	}
	input := filepath.Join(t.TempDir(), "input.env")
	if err := os.WriteFile(input, []byte(content+"DEBUG=false\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(installinput.EnvConfig, input)
	err = validateFreshInstallInput(dir, false)
	if err == nil || !strings.Contains(err.Error(), "extra key DEBUG") {
		t.Fatalf("extra: %v", err)
	}
	if err := runCreateConfig(dir); err == nil {
		t.Fatal("extra config accepted")
	}
	if _, err := os.Stat(filepath.Join(dir, ".env.config")); !os.IsNotExist(err) {
		t.Fatalf("invalid input wrote config: %v", err)
	}
	if err := os.WriteFile(input, []byte(content+"TRUST_GITHUB_USER=jhf\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(installinput.UsersFile, filepath.Join(dir, "missing-users"))
	if err := validateFreshInstallInput(dir, false); err == nil || !strings.Contains(err.Error(), "STATBUS_USERS_FILE") {
		t.Fatalf("users: %v", err)
	}
}

func TestUnattendedRepairPreservesExistingConfig(t *testing.T) {
	dir, _ := unattendedFixture(t)
	path := filepath.Join(dir, ".env.config")
	if err := os.WriteFile(path, []byte("existing config including tuning"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(installinput.EnvConfig, "missing-stale-input")
	if err := validateFreshInstallInput(dir, false); err != nil {
		t.Fatalf("repair requested fresh input: %v", err)
	}
	if err := validateFreshInstallInput(t.TempDir(), true); err != nil {
		t.Fatalf("internal fixup requested fresh input: %v", err)
	}
}

func TestUnattendedCommandRefusesBeforeInfrastructure(t *testing.T) {
	home, _ := unattendedFixture(t)
	t.Setenv("HOME", home)
	t.Setenv("STATBUS_POST_UPGRADE_FIXUP", "")
	old := postUpgradeFixup
	postUpgradeFixup = false
	t.Cleanup(func() { postUpgradeFixup = old })
	err := runInstall()
	if err == nil || !strings.Contains(err.Error(), installinput.Requirement()) {
		t.Fatalf("runInstall no env: %v", err)
	}
	if _, err := os.Stat(filepath.Join(home, "statbus")); !os.IsNotExist(err) {
		t.Fatalf("early validation mutated install directory: %v", err)
	}
}
