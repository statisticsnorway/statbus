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
	content := installinput.Ask(func(label, fallback string) string {
		if strings.HasSuffix(label, "Domain name") {
			return "example.org"
		}
		return fallback
	})
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
	for name, want := range map[string]string{".env.config": content + "DEPLOYMENT_SLOT_PORT_OFFSET=1\nSTATBUS_DISK_MIN_GB=20\nSTATBUS_DISK_RECOMMENDED_GB=40\n", ".users.yml": "users fixture"} {
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

func TestFreshInstallInputDistinguishesExplicitEnvAndPipe(t *testing.T) {
	oldNonInteractive := nonInteractive
	oldTrust := trustGitHubUser
	oldStdinIsTerminal := stdinIsTerminal
	t.Cleanup(func() {
		nonInteractive = oldNonInteractive
		trustGitHubUser = oldTrust
		stdinIsTerminal = oldStdinIsTerminal
	})
	dir := t.TempDir()
	stdinIsTerminal = func() bool { return false }
	t.Setenv(installinput.UsersFile, "")

	// An explicit flag gets the unattended recipe because the operator asked
	// for unattended mode.
	nonInteractive = true
	trustGitHubUser = ""
	t.Setenv(installinput.EnvConfig, "")
	err := validateFreshInstallInput(dir, false)
	if err == nil || !strings.Contains(err.Error(), installinput.Requirement()) {
		t.Fatalf("explicit --non-interactive: %v", err)
	}
	if strings.Contains(err.Error(), installinput.StdinNotTerminalMessage) {
		t.Fatalf("explicit --non-interactive misreported as a pipe: %v", err)
	}
	if !strings.Contains(err.Error(), "--trust-github-user <github-user>") {
		t.Fatalf("explicit flag path omitted its compatible trust flag: %v", err)
	}

	// An answer file is read even though stdin is not a terminal, and its own
	// validation error wins over any generic pipe diagnosis.
	nonInteractive = false
	input := filepath.Join(t.TempDir(), "input.env")
	content := installinput.Ask(func(label, fallback string) string {
		if strings.HasSuffix(label, "Domain name") {
			return "example.org"
		}
		return fallback
	})
	if err := os.WriteFile(input, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(installinput.EnvConfig, input)
	err = validateFreshInstallInput(dir, false)
	if err == nil || !strings.Contains(err.Error(), "missing key TRUST_GITHUB_USER") {
		t.Fatalf("STATBUS_ENV_CONFIG without signer: %v", err)
	}
	if strings.Contains(err.Error(), installinput.StdinNotTerminalMessage) {
		t.Fatalf("STATBUS_ENV_CONFIG misreported as a pipe: %v", err)
	}
	for _, forbidden := range []string{"--non-interactive", "--trust-github-user"} {
		if strings.Contains(err.Error(), forbidden) {
			t.Fatalf("STATBUS_ENV_CONFIG help invented unpassed flag %s: %v", forbidden, err)
		}
	}
	for _, want := range []string{"TRUST_GITHUB_USER=<github-user>", input, installinput.TrustExplanation} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("STATBUS_ENV_CONFIG remedy missing %q: %v", want, err)
		}
	}

	// Neither an explicit flag nor an answer file means a non-terminal stdin is
	// accidental, commonly curl|bash without a controlling terminal.
	t.Setenv(installinput.EnvConfig, "")
	err = validateFreshInstallInput(dir, false)
	if err == nil || err.Error() != installinput.StdinNotTerminalMessage {
		t.Fatalf("piped stdin: got %v, want exact pipe remedy", err)
	}
	if strings.Contains(err.Error(), "--non-interactive") {
		t.Fatalf("pipe remedy told operator to pass an unrequested flag: %v", err)
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
	if got := ExitCode(err); got != exitInstallPreflight {
		t.Fatalf("preflight ExitCode = %d, want %d", got, exitInstallPreflight)
	}
	if _, err := os.Stat(filepath.Join(home, "statbus", "tmp", "install-terminal.txt")); !os.IsNotExist(err) {
		t.Fatalf("preflight refusal wrote invariant marker: %v", err)
	}
}
