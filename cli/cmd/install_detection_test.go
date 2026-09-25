package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func withRunInstallDetectionHooks(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("STATBUS_MIN_DISK_GB", "0")
	installDir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(installDir, 0o755); err != nil {
		t.Fatal(err)
	}
	fixtureCheckout(t, installDir)
	oldExe := installExecutable
	installExecutable = func() (string, error) { return filepath.Join(installDir, "sb"), nil }
	t.Cleanup(func() { installExecutable = oldExe })
	if err := os.WriteFile(filepath.Join(installDir, "sb"), nil, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(installDir, ".env.config"), []byte("CADDY_DEPLOYMENT_MODE=development\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = info ]; then printf '%s\\n' \"$STATBUS_TEST_DOCKER_ROOT\"; fi\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STATBUS_TEST_DOCKER_ROOT", home)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	originalDetect := detectInstallState
	originalBundle := writeDetectionSupportBundle
	originalSigners := checkInstallSigners
	originalStepHook := runInstallStepTableTestHook
	originalVersion := version
	originalNonInteractive := nonInteractive
	originalTrust := trustGitHubUser
	originalFixup := postUpgradeFixup
	t.Cleanup(func() {
		detectInstallState = originalDetect
		writeDetectionSupportBundle = originalBundle
		checkInstallSigners = originalSigners
		runInstallStepTableTestHook = originalStepHook
		version = originalVersion
		nonInteractive = originalNonInteractive
		trustGitHubUser = originalTrust
		postUpgradeFixup = originalFixup
	})
	version = "dev"
	nonInteractive = true
	trustGitHubUser = ""
	postUpgradeFixup = false
	checkInstallSigners = func(string) bool { return true }
	return installDir
}

type installProbe struct {
	flagErr, dbErr, tableErr, historyErr, scheduledErr, restoreErr error
	upgradeTable                                                   bool
	configErr, credentialsErr                                      error
}

func TestRunInstallSignerPreflightAfterPortRefusal(t *testing.T) {
	for _, tc := range []struct {
		name      string
		state     install.State
		pending   bool
		wantSteps int
	}{
		{"config saved before credentials", install.StateHalfConfigured, true, 1},
		{"database not yet reachable", install.StateDBUnreachable, true, 1},
		{"first database incomplete", install.StateFreshDBIncomplete, true, 1},
		{"established database down", install.StateDBUnreachable, false, 0},
		{"established credentials missing", install.StateHalfConfigured, false, 0},
		{"existing installation", install.StateNothingScheduled, false, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := withRunInstallDetectionHooks(t)
			if tc.pending {
				if err := os.WriteFile(filepath.Join(dir, firstInstallSignerPending), []byte("pending\n"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			checkInstallSigners = func(string) bool { return false }
			detectInstallState = func(string, string) (install.State, *install.Detail, error) {
				return tc.state, &install.Detail{}, nil
			}
			steps := 0
			runInstallStepTableTestHook = func() error { steps++; return nil }
			err := runInstall()
			if steps != tc.wantSteps {
				t.Fatalf("steps=%d, want %d; err=%v", steps, tc.wantSteps, err)
			}
			if tc.wantSteps == 0 && (err == nil || !strings.Contains(err.Error(), "No valid release signer")) {
				t.Fatalf("existing install must refuse without signer: %v", err)
			}
			if tc.wantSteps == 1 && err != nil {
				t.Fatalf("incomplete installation could not resume: %v", err)
			}
		})
	}
}

func TestSavedSignerConsentSurvivesCompletedConfig(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("CADDY_DEPLOYMENT_MODE=standalone\n"), 0600); err != nil {
		t.Fatal(err)
	}
	answers := filepath.Join(t.TempDir(), "install-input.env")
	content := "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=example.org\nDEPLOYMENT_SLOT_NAME=Install Test\nDEPLOYMENT_SLOT_CODE=test\nTRUST_GITHUB_USER=jhf\n"
	if err := os.WriteFile(answers, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STATBUS_ENV_CONFIG", answers)
	if err := os.WriteFile(filepath.Join(dir, firstInstallSignerPending), []byte("pending\n"), 0600); err != nil {
		t.Fatal(err)
	}
	previous := trustGitHubUser
	trustGitHubUser = ""
	t.Cleanup(func() { trustGitHubUser = previous })
	if err := validateFreshInstallInput(dir, false); err != nil {
		t.Fatal(err)
	}
	if trustGitHubUser != "" {
		t.Fatal("consent imported before state classification")
	}
	if err := importPendingSignerConsent(dir); err != nil {
		t.Fatal(err)
	}
	if trustGitHubUser != "jhf" {
		t.Fatalf("saved signer consent was lost: %q", trustGitHubUser)
	}
}

func TestEstablishedInstallIgnoresStaleSignerAnswers(t *testing.T) {
	dir := withRunInstallDetectionHooks(t)
	answers := filepath.Join(t.TempDir(), "answers.env")
	if err := os.WriteFile(answers, []byte("TRUST_GITHUB_USER=jhf\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STATBUS_ENV_CONFIG", answers)
	checkInstallSigners = func(string) bool { return false }
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		return install.StateNothingScheduled, &install.Detail{}, nil
	}
	runInstallStepTableTestHook = func() error { t.Fatal("established installation reached steps"); return nil }
	err := runInstall()
	if err == nil || !strings.Contains(err.Error(), "No valid release signer") {
		t.Fatalf("expected explicit signer refusal: %v", err)
	}
	if trustGitHubUser != "" {
		t.Fatalf("stale consent imported: %q", trustGitHubUser)
	}
	if signerPreflightRequired(dir, install.StateDBUnreachable) != true {
		t.Fatal("lost database must not establish first-install provenance")
	}
}

func (p installProbe) FileExists(path string) (bool, error) {
	if filepath.Base(path) == ".env.config" {
		return true, p.configErr
	}
	return true, p.credentialsErr
}
func (p installProbe) ReadFlag(string) (*upgrade.UpgradeFlag, bool, error) {
	return nil, false, p.flagErr
}
func (p installProbe) DBReachable(string) (bool, error)     { return true, p.dbErr }
func (p installProbe) HasUpgradeTable(string) (bool, error) { return p.upgradeTable, p.tableErr }
func (p installProbe) InspectSchemaHistory(string) (install.SchemaHistory, error) {
	return install.SchemaHistory{}, p.historyErr
}
func (p installProbe) QueryScheduledUpgrade(string) (*install.ScheduledRow, error) {
	return nil, p.scheduledErr
}
func (p installProbe) QueryReattemptableRestore(string) (int64, string, bool, error) {
	return 0, "", false, p.restoreErr
}

func TestRunInstallProbeErrorsFailClosed(t *testing.T) {
	cases := []struct {
		name     string
		probe    installProbe
		fallback bool
	}{
		{"config stat failure", installProbe{configErr: errors.New("permission denied")}, false},
		{"credentials stat failure", installProbe{credentialsErr: errors.New("permission denied")}, false},
		{"flag malformed", installProbe{flagErr: errors.New("invalid flag JSON")}, false},
		{"flag read failure", installProbe{flagErr: errors.New("permission denied")}, false},
		{"reachability malformed", installProbe{dbErr: errors.New("unexpected SELECT 1 output")}, false},
		{"reachability query failure", installProbe{dbErr: errors.New("SQL permission denied")}, false},
		{"table malformed", installProbe{tableErr: errors.New("unexpected upgrade table output")}, false},
		{"table query failure", installProbe{tableErr: errors.New("SQL error")}, false},
		{"schema malformed", installProbe{historyErr: errors.New("unexpected schema output")}, false},
		{"schema query failure", installProbe{historyErr: errors.New("SQL error")}, false},
		{"scheduled malformed", installProbe{upgradeTable: true, scheduledErr: errors.New("unexpected scheduled row")}, false},
		{"scheduled query failure", installProbe{upgradeTable: true, scheduledErr: errors.New("SQL error")}, false},
		{"restore malformed", installProbe{upgradeTable: true, restoreErr: errors.New("unexpected restore row")}, false},
		{"restore query failure", installProbe{upgradeTable: true, restoreErr: errors.New("SQL error")}, false},
		{"confirmed unavailable", installProbe{dbErr: fmt.Errorf("connect: %w", install.ErrDatabaseUnavailable)}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			installDir := withRunInstallDetectionHooks(t)
			detectInstallState = func(dir, v string) (install.State, *install.Detail, error) {
				return install.DetectWith(dir, v, tc.probe)
			}
			bundlePath := filepath.Join(installDir, "support-bundle-test.txt")
			writeDetectionSupportBundle = func(string) (string, error) { return bundlePath, nil }
			steps := 0
			runInstallStepTableTestHook = func() error { steps++; return nil }
			err := runInstall()
			if tc.fallback {
				if err != nil || steps != 1 {
					t.Fatalf("fallback: err=%v steps=%d", err, steps)
				}
			} else {
				if err == nil || steps != 0 {
					t.Fatalf("refusal: err=%v steps=%d", err, steps)
				}
				for _, want := range []string{"could not be determined", "nothing was changed", "Run the same install command again", bundlePath} {
					if !strings.Contains(err.Error(), want) {
						t.Errorf("missing %q in %v", want, err)
					}
				}
			}
		})
	}
}

func TestRunInstallStopsBeforeStepsWhenDatabaseAnswerCannotBeClassified(t *testing.T) {
	installDir := withRunInstallDetectionHooks(t)
	bundlePath := filepath.Join(installDir, "support-bundle-test.txt")
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		return 0, nil, errors.New(`unexpected schema probe output: "junk|junk"`)
	}
	writeDetectionSupportBundle = func(string) (string, error) {
		if err := os.WriteFile(bundlePath, []byte("diagnostics"), 0o600); err != nil {
			return "", err
		}
		return bundlePath, nil
	}
	stepExecuted := false
	runInstallStepTableTestHook = func() error {
		stepExecuted = true
		return nil
	}

	err := runInstall()
	if err == nil {
		t.Fatal("runInstall succeeded after an unclassifiable database response")
	}
	if stepExecuted {
		t.Fatal("step table was reached after an unclassifiable database response")
	}
	for _, want := range []string{
		"the install state could not be determined",
		"nothing was changed",
		"Run the same install command again: curl -fsSL https://statbus.org/install.sh | bash",
		"send this file to StatBus support: " + bundlePath,
	} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error missing %q:\n%s", want, err)
		}
	}
	if strings.Contains(err.Error(), "unexpected schema probe output") {
		t.Fatal("internal probe error leaked into the operator refusal")
	}
	if _, statErr := os.Stat(bundlePath); statErr != nil {
		t.Fatalf("support bundle was not written: %v", statErr)
	}
}

func TestRunInstallKeepsUnavailableProbeStepTableFallback(t *testing.T) {
	_ = withRunInstallDetectionHooks(t)
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		return 0, nil, fmt.Errorf("check public.upgrade existence: %w", install.ErrDatabaseUnavailable)
	}
	bundleCalled := false
	writeDetectionSupportBundle = func(string) (string, error) {
		bundleCalled = true
		return "", nil
	}
	stepExecuted := false
	runInstallStepTableTestHook = func() error {
		stepExecuted = true
		return nil
	}

	if err := runInstall(); err != nil {
		t.Fatalf("runInstall unavailable-probe fallback: %v", err)
	}
	if !stepExecuted {
		t.Fatal("unavailable probe did not continue to the repair step table")
	}
	if bundleCalled {
		t.Fatal("unavailable probe incorrectly used the unclassifiable-response refusal path")
	}
}
