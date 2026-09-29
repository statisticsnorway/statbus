package cmd

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
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
	originalRecover := recoverCrashedInstall
	originalBundle := writeDetectionSupportBundle
	originalSigners := checkInstallSigners
	originalStepHook := runInstallStepTableTestHook
	originalVersion := version
	originalNonInteractive := nonInteractive
	originalTrust := trustGitHubUser
	originalFixup := postUpgradeFixup
	originalRestore := restoreGeneratedSettings
	t.Cleanup(func() {
		restoreGeneratedSettings = originalRestore
		detectInstallState = originalDetect
		recoverCrashedInstall = originalRecover
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

func TestRunInstallImportsConsentAfterInstallFlagRecovery(t *testing.T) {
	for _, tc := range []struct {
		name       string
		state      install.State
		marker     bool
		wantResume bool
	}{
		{"first install with pending consent", install.StateFreshDBIncomplete, true, true},
		{"first install without marker", install.StateFreshDBIncomplete, false, false},
		{"established box with stale marker", install.StateNothingScheduled, true, false},
		{"established box without marker", install.StateNothingScheduled, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := withRunInstallDetectionHooks(t)
			answers := filepath.Join(t.TempDir(), "install-input.env")
			if err := os.WriteFile(answers, []byte("CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=example.org\nDEPLOYMENT_SLOT_NAME=Install Test\nDEPLOYMENT_SLOT_CODE=test\nTRUST_GITHUB_USER=jhf\n"), 0600); err != nil {
				t.Fatal(err)
			}
			t.Setenv("STATBUS_ENV_CONFIG", answers)
			if tc.marker {
				if err := os.WriteFile(filepath.Join(dir, firstInstallSignerPending), []byte("pending\n"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			// Trust is checked without a network request. Only consent imported
			// after recovery may make this fake signer available to the preflight.
			checkInstallSigners = func(string) bool { return trustGitHubUser == "jhf" }
			probes := 0
			detectInstallState = func(string, string) (install.State, *install.Detail, error) {
				probes++
				if probes == 1 {
					return install.StateCrashedUpgrade, &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: upgrade.HolderInstall}}, nil
				}
				return tc.state, &install.Detail{}, nil
			}
			recoveries := 0
			recoverCrashedInstall = func(string, *func()) error { recoveries++; return nil }
			steps := 0
			runInstallStepTableTestHook = func() error {
				steps++
				if trustGitHubUser != "jhf" {
					t.Fatalf("step table lost saved consent: %q", trustGitHubUser)
				}
				return nil
			}
			err := runInstall()
			if probes != 2 || recoveries != 1 {
				t.Fatalf("probes=%d recoveries=%d err=%v", probes, recoveries, err)
			}
			if tc.wantResume {
				if err != nil || steps != 1 {
					t.Fatalf("interrupted install failed to resume: steps=%d err=%v", steps, err)
				}
			} else if err == nil || !strings.Contains(err.Error(), "No valid release signer") || steps != 0 {
				t.Fatalf("non-provenanced install must refuse: steps=%d err=%v", steps, err)
			}
		})
	}
}

func TestRecoveryBootMigrateLeavesInstallFlagForStepTable(t *testing.T) {
	dir := t.TempDir()
	check := func(want bool) {
		t.Helper()
		got, err := recoveryBootMigrateRequired(dir)
		if err != nil || got != want {
			t.Fatalf("boot migrate required=%t, want %t: %v", got, want, err)
		}
	}
	check(true) // No install-held provenance, retain the old recovery path.
	lock, err := upgrade.AcquireInstallFlag(dir, "first-install")
	if err != nil {
		t.Fatal(err)
	}
	lock.Close() // Genuine stale install flag, without touching the database.
	check(false)
	path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
	serviceFlag, err := json.Marshal(upgrade.UpgradeFlag{Holder: upgrade.HolderService, ID: 1})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, serviceFlag, 0600); err != nil {
		t.Fatal(err)
	}
	check(true) // A real upgrade still needs its schema-floor migration.
	if err := os.WriteFile(path, []byte("not JSON"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := recoveryBootMigrateRequired(dir); err == nil {
		t.Fatal("malformed recovery marker must fail closed")
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
		"Run the same install command again: " + diskpolicy.RerunCommand(),
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

// rc.15 arc run 36442434055 and review tmp/review-detect-env.md: with
// .env.config and .env.credentials but no generated .env, the database probe
// had no route and install refused itself on every rerun. The generated .env
// is now restored first, and Detect decides from the real database state:
// an established box keeps its refusals and dispatches (legacy shown here),
// an unfinished one continues. Nothing is classified from the missing file.
func TestRunInstallRestoresSettingsBeforeDetect(t *testing.T) {
	for _, tc := range []struct {
		name      string
		state     install.State
		wantSteps int
		wantErr   string
	}{
		{"unfinished first install continues", install.StateFreshDBIncomplete, 1, ""},
		{"established pre-1.0 database still refused", install.StateLegacyNoUpgradeTable, 0, "pre-1.0 install detected"},
		{"established installation checked normally", install.StateNothingScheduled, 1, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := withRunInstallDetectionHooks(t)
			if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("GITHUB_TOKEN=arc-token\n"), 0o600); err != nil {
				t.Fatal(err)
			}
			var order []string
			restoreGeneratedSettings = func(d string) error {
				order = append(order, "restore")
				return os.WriteFile(filepath.Join(d, ".env"), []byte("POSTGRES_APP_DB=statbus_test\n"), 0o600)
			}
			detectInstallState = func(d, _ string) (install.State, *install.Detail, error) {
				if _, err := os.Stat(filepath.Join(d, ".env")); err != nil {
					t.Fatalf("Detect ran without the generated .env: %v", err)
				}
				order = append(order, "detect")
				return tc.state, &install.Detail{}, nil
			}
			steps := 0
			runInstallStepTableTestHook = func() error { steps++; return nil }
			err := runInstall()
			if strings.Join(order, ",") != "restore,detect" {
				t.Fatalf("order = %v, want restore then detect", order)
			}
			if steps != tc.wantSteps {
				t.Fatalf("steps = %d, want %d (err=%v)", steps, tc.wantSteps, err)
			}
			if tc.wantErr == "" && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.wantErr != "" && (err == nil || !strings.Contains(err.Error(), tc.wantErr)) {
				t.Fatalf("error = %v, want %q", err, tc.wantErr)
			}
		})
	}
}

// A settings error (for example a host path in TLS_CERT_FILE) stops before
// detection, shows the actual cause and the rerun command, and changes
// nothing else: no probe, no step table.
func TestRunInstallSettingsRestoreFailureRefusesWithCause(t *testing.T) {
	dir := withRunInstallDetectionHooks(t)
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("X=1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	restoreGeneratedSettings = func(string) error {
		return errors.New(`TLS_CERT_FILE="/home/statbus/statbus.crt" is not a valid Caddy container path`)
	}
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		t.Fatal("Detect ran after settings could not be restored")
		return 0, nil, nil
	}
	runInstallStepTableTestHook = func() error { t.Fatal("step table ran"); return nil }
	err := runInstall()
	var preflight *installPreflightRefusalError
	if !errors.As(err, &preflight) {
		t.Fatalf("want preflight refusal, got %v", err)
	}
	for _, want := range []string{"TLS_CERT_FILE=\"/home/statbus/statbus.crt\" is not a valid Caddy container path", "The database and services were not touched", "Correct the settings, then run: " + diskpolicy.RerunCommand()} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal missing %q: %v", want, err)
		}
	}
}

// Settings restoration is only for a box missing exactly the generated file.
func TestRestoreSettingsBeforeDetectOnlyWhenOnlyEnvIsMissing(t *testing.T) {
	for _, tc := range []struct {
		name        string
		credentials bool
		env         bool
		flag        bool
		want        bool
	}{
		{"config and credentials, no .env", true, false, false, true},
		{"generated .env present", true, true, false, false},
		{"credentials missing (half-configured path)", false, false, false, false},
		{"upgrade flag present (crash recovery path)", true, false, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := withRunInstallDetectionHooks(t)
			write := func(rel string) {
				p := filepath.Join(dir, rel)
				if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(p, []byte("X=1\n"), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			if tc.credentials {
				write(".env.credentials")
			}
			if tc.env {
				write(".env")
			}
			if tc.flag {
				write("tmp/upgrade-in-progress.json")
			}
			called := false
			restoreGeneratedSettings = func(string) error { called = true; return nil }
			if err := restoreSettingsBeforeDetect(dir); err != nil {
				t.Fatal(err)
			}
			if called != tc.want {
				t.Fatalf("restore called = %v, want %v", called, tc.want)
			}
		})
	}
}

// The real Settings code turns the arc layout (.env.config plus a token-only
// .env.credentials, no .env) into a generated .env carrying the database
// route, without touching the operator's token.
func TestRestoreSettingsBeforeDetectWritesRealRoute(t *testing.T) {
	dir := withRunInstallDetectionHooks(t)
	root := filepath.Join("..", "..")
	example, err := os.ReadFile(filepath.Join(root, ".env.example"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.example"), example, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(dir, "caddy", "templates"), os.DirFS(filepath.Join(root, "caddy", "templates"))); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "ops", "maintenance"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("GITHUB_TOKEN=arc-token\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := restoreSettingsBeforeDetect(dir); err != nil {
		t.Fatalf("restore: %v", err)
	}
	env, err := dotenv.Load(filepath.Join(dir, ".env"))
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"POSTGRES_APP_DB", "POSTGRES_ADMIN_PASSWORD", "COMPOSE_INSTANCE_NAME"} {
		if v, ok := env.Get(key); !ok || v == "" {
			t.Errorf("generated .env lacks %s", key)
		}
	}
	creds, err := dotenv.Load(filepath.Join(dir, ".env.credentials"))
	if err != nil {
		t.Fatal(err)
	}
	if v, _ := creds.Get("GITHUB_TOKEN"); v != "arc-token" {
		t.Fatalf("operator token changed: %q", v)
	}
}

// Review finding 2: the restore is serialised through the install mutex,
// claimed fresh-only. A marker held by another install or upgrade means this
// run neither restores nor touches the marker; Detect classifies it.
func TestRestoreSettingsBeforeDetectYieldsToAnotherHolder(t *testing.T) {
	dir := withRunInstallDetectionHooks(t)
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("X=1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	other, err := upgrade.AcquireInstallFlag(dir, "other-install")
	if err != nil {
		t.Fatal(err)
	}
	defer upgrade.ReleaseInstallFlag(other)
	called := false
	restoreGeneratedSettings = func(string) error { called = true; return nil }
	if err := restoreSettingsBeforeDetect(dir); err != nil {
		t.Fatal(err)
	}
	if called {
		t.Fatal("restored settings while another installer held the mutex")
	}
	flag, err := upgrade.ReadFlagFile(dir)
	if err != nil || flag == nil || flag.InvokedBy != "other-install" {
		t.Fatalf("other holder's marker was disturbed: %+v, %v", flag, err)
	}
	if !upgrade.IsFlockHeld(dir) {
		t.Fatal("other holder lost the mutex")
	}
}

// While restoring, this run holds the mutex, so a concurrent install cannot
// enter; afterwards the marker is gone, so Detect never sees its own claim.
func TestRestoreSettingsBeforeDetectHoldsThenReleasesMutex(t *testing.T) {
	dir := withRunInstallDetectionHooks(t)
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("X=1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	restoreGeneratedSettings = func(d string) error {
		if !upgrade.IsFlockHeld(d) {
			t.Error("settings were restored without holding the install mutex")
		}
		if _, err := upgrade.AcquireInstallFlag(d, "concurrent-install"); err == nil {
			t.Error("a concurrent install acquired the mutex during the restore")
		}
		return os.WriteFile(filepath.Join(d, ".env"), []byte("X=1\n"), 0o600)
	}
	if err := restoreSettingsBeforeDetect(dir); err != nil {
		t.Fatal(err)
	}
	if flag, err := upgrade.ReadFlagFile(dir); err != nil || flag != nil {
		t.Fatalf("marker left behind for Detect to misread: %+v, %v", flag, err)
	}
	if !settingsRestoredBeforeDetect {
		t.Fatal("restore not recorded for Apply config changes")
	}
}

// Review finding 1: after a restore the step-table snapshot is the restored
// .env, so the forced set must recreate every service and the daemon.
func TestRestartsAfterSettingsRestoreCoverEveryService(t *testing.T) {
	got := restartsAfterSettingsRestore()
	for _, c := range []config.RestartClass{config.RestartDB, config.RestartRest, config.RestartWorker, config.RestartApp, config.RestartProxyRestart, config.RestartUpgradeDaemon} {
		if !got[c] {
			t.Errorf("restart class %s not forced after a settings restore", c)
		}
	}
	applied := map[string]bool{}
	orig := composeApplyService
	composeApplyService = func(_, service string) error { applied[service] = true; return nil }
	defer func() { composeApplyService = orig }()
	if err := applyPendingRestarts(t.TempDir(), got); err != nil {
		t.Fatal(err)
	}
	for _, s := range []string{"db", "rest", "worker", "app", "proxy"} {
		if !applied[s] {
			t.Errorf("service %s not recreated", s)
		}
	}
}

// Review finding 3: what the operator sees. The real TLS validator errors
// classify to the fixed certificate cause, and install.sh's exit-78 branch
// (extracted verbatim) prints that cause and fix, never the raw error.
func TestSettingsRestoreRefusalShowsCertificateCauseThroughInstallSh(t *testing.T) {
	for _, raw := range []string{
		`TLS_CERT_FILE="/home/statbus/statbus.crt" is not a valid Caddy container path. Run ` + "`cd /home/statbus/statbus && ./sb cert install <full path to certificate> <full path to key>`" + ` (or a single PFX/PKCS#12 file); it places the files, sets TLS_CERT_FILE/TLS_KEY_FILE, and restarts Caddy for you. See doc/DEPLOYMENT.md, Custom TLS Certificates.`,
		`TLS_KEY_FILE="/data/custom-certs/domain.key": corresponding host file /home/statbus/statbus/caddy/data/custom-certs/domain.key is unavailable: no such file`,
		`both TLS_CERT_FILE and TLS_KEY_FILE must be set together. Run ` + "`cd /home/statbus/statbus && ./sb cert install <full path to certificate> <full path to key>`" + ` (or a single PFX/PKCS#12 file); it places the files, sets TLS_CERT_FILE/TLS_KEY_FILE, and restarts Caddy for you. See doc/DEPLOYMENT.md, Custom TLS Certificates.`,
	} {
		if cause, _ := classifyInstallFailure("Settings", errors.New(raw)); cause != "The custom certificate settings are invalid." {
			t.Errorf("TLS error not classified: %q -> %q", raw, cause)
		}
	}
	script, err := os.ReadFile("../../install.sh")
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(script), "\n")
	start, end := -1, -1
	for i, l := range lines {
		if start < 0 && l == `if [ "$sb_rc" -eq 78 ]; then` {
			start = i
		} else if start >= 0 && l == "fi" {
			end = i
			break
		}
	}
	if start < 0 || end < 0 {
		t.Fatal("exit-78 branch not found in install.sh")
	}
	dir := t.TempDir()
	logPath := filepath.Join(dir, "install-last-run-output.txt")
	cause, fix := classifyInstallFailure("Settings", errors.New(`TLS_CERT_FILE="/home/statbus/statbus.crt" is not a valid Caddy container path`))
	log := "Restoring generated settings before checking the installation.\nINSTALL_CAUSE: " + cause + "\nINSTALL_FIX: " + fix + "\nthe settings could not be restored: TLS_CERT_FILE=\"/home/statbus/statbus.crt\" is not a valid Caddy container path. The database and services were not touched.\n"
	if err := os.WriteFile(logPath, []byte(log), 0o600); err != nil {
		t.Fatal(err)
	}
	branch := strings.Join(lines[start:end+1], "\n")
	cmd := exec.Command("bash", "-c", "sb_rc=78\ninstall_output=\"$1\"\nSTATBUS_DIR=\"$2\"\nSTATBUS_INSTALL_RERUN_COMMAND='curl -fsSL https://statbus.org/install.sh | bash'\n"+branch, "exit78", logPath, dir)
	out, _ := cmd.Output()
	got := string(out)
	for _, want := range []string{"Installation cannot start: The custom certificate settings are invalid.", "cd ~/statbus && ./sb cert install", "Then run: curl -fsSL https://statbus.org/install.sh | bash"} {
		if !strings.Contains(got, want) {
			t.Errorf("operator output missing %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "/home/statbus/statbus.crt") {
		t.Errorf("raw error text reached the operator:\n%s", got)
	}
}

// TestExit78AllowlistMatchesRealGoSentences drives install.sh's exit-78
// bucket (port / disk-shortfall / disk-unmeasurable / restart-still-running)
// with the REAL error strings the Go producers construct, not hand-copied
// literals — portConflictGuidance's two remedy shapes plus the
// probe-could-not-check variant, diskpolicy.Evaluate's shortfall sentence,
// diskpolicy.DockerRoot's unmeasurable sentence, and install.go's two restart
// sentences (preflight barrier vs. the install.sh bootstrap mutex). Confirms
// the STATBUS-430 review's full-line anchoring (change A) did not silently
// stop matching any real production sentence.
func TestExit78AllowlistMatchesRealGoSentences(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash -s --version v2026.09.3"
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", rerun)
	dir := t.TempDir()
	real := []struct {
		name string
		line string
	}{
		{"port systemctl remedy", fmt.Sprintf("%s Your answers are saved. Then run the same install command again: %s", portConflictGuidance(80, "nginx"), rerun)},
		{"port kill remedy", fmt.Sprintf("%s Your answers are saved. Then run the same install command again: %s", portConflictGuidance(3014, "python3"), rerun)},
		{"port another-program remedy", fmt.Sprintf("%s Your answers are saved. Then run the same install command again: %s", portConflictGuidance(3014, "another program"), rerun)},
		{"port ownership could not be checked", fmt.Sprintf("%s Docker service ownership could not be checked. Your answers are saved. Then run the same install command again: %s", portConflictGuidance(3014, "another program"), rerun)},
	}
	shortfall, ok := diskpolicy.Evaluate(diskpolicy.Measurement{Path: "/var/lib/docker", FreeGB: 4})
	if ok {
		t.Fatal("expected a disk shortfall (ok=false) at 4 GB free")
	}
	real = append(real, struct {
		name string
		line string
	}{"disk shortfall", shortfall})
	real = append(real,
		struct{ name, line string }{"disk unmeasurable (Docker root)", "cannot check disk space at Docker storage: Docker root unavailable"},
		struct{ name, line string }{"disk unmeasurable (measurement)", "cannot check disk space at /home/statbus/statbus-backups: measurement unavailable"},
		struct{ name, line string }{"restart preflight barrier", fmt.Sprintf("a restart is still running, or its services could not be restored. Wait for it to finish, then run the same install command again: %s", rerun)},
		struct{ name, line string }{"restart bootstrap mutex", fmt.Sprintf("a restart is still running. Wait for it to finish, then run the same install command again: %s", rerun)},
	)
	for _, tc := range real {
		t.Run(tc.name, func(t *testing.T) {
			got := installShFailureTailIn(t, dir, rerun, tc.line+"\n", 78)
			if !strings.Contains(got, tc.line) {
				t.Errorf("full-line anchoring stopped matching a real Go sentence:\n  sentence: %s\n  output:   %s", tc.line, got)
			}
			if strings.Contains(got, "Correct the settings") {
				t.Errorf("a real allowlisted sentence fell through to the generic settings refusal:\n%s", got)
			}
		})
	}
}

// TestStateDetectionFailureRerunsRatherThanBlamesSettings drives the REAL
// Go path: a probe error (Ville replay D4's exact raw psql text: "FATAL: the
// database system is shutting down" mid binary-swap, which is not a proven
// outage — install.DetectWith wraps it as an ordinary error, not
// install.ErrDatabaseUnavailable) reaches runInstall, whose returned error is
// rendered by the real printInstallFailure exactly as ./sb install would
// print it to stdout/stderr, then piped through install.sh's own exit-78
// branch (installShFailureTail, the same extraction technique as
// TestInstallShShowsNamedRefusal). Nothing here re-types install.go's format
// string: if a future edit changes runInstall's wording, this test observes
// that changed text landing (or failing to land) on the operator, not a
// frozen copy of the old text.
func TestStateDetectionFailureRerunsRatherThanBlamesSettings(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash"
	installDir := withRunInstallDetectionHooks(t)
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", rerun)
	bundlePath := filepath.Join(installDir, "support-bundle-20260929-080619.txt")
	writeDetectionSupportBundle = func(string) (string, error) {
		if err := os.WriteFile(bundlePath, []byte("bundle"), 0o600); err != nil {
			return "", err
		}
		return bundlePath, nil
	}
	// Ville's raw probe failure, byte for byte (replay D4): a DB restart
	// mid binary-swap answers a detection query with this, and
	// connectionUnavailable's marker list does NOT include it, so
	// install.DetectWith wraps it as an ordinary (non-Unavailable) error —
	// exactly the "not a proven outage" branch this refusal exists for.
	const villeRawLine = `psql: FATAL: the database system is shutting down`
	detectInstallState = func(dir, v string) (install.State, *install.Detail, error) {
		return install.DetectWith(dir, v, installProbe{dbErr: errors.New(villeRawLine)})
	}
	runInstallStepTableTestHook = func() error { t.Fatal("step table reached after an unresolved detection probe error"); return nil }

	err := runInstall()
	if err == nil {
		t.Fatal("runInstall succeeded despite an unresolved detection probe error")
	}
	// In production, install.sh's own `tee -a` appends ./sb install's stdout
	// to this same diagnostics file that installDiagnostic already wrote
	// Ville's raw probe line into (install.go:542). Reproduce that ordering
	// here: read what installDiagnostic wrote, then append what this test's
	// sbOutput buffer would additionally contribute, before handing the
	// combined file content to installShFailureTailIn. Without this, the
	// diagnostics file installShFailureTailIn writes from sbOutput alone
	// *replaces* the raw line instead of accumulating after it, and the
	// negative assertion below can never observe a real leak.
	priorDiagnostics, err2 := os.ReadFile(filepath.Join(installDir, "tmp", "install-last-run-output.txt"))
	if err2 != nil {
		t.Fatalf("reading installDiagnostic's file: %v", err2)
	}
	var sbOutput bytes.Buffer
	sbOutput.Write(priorDiagnostics)
	sbOutput.WriteString("Restoring generated settings before checking the installation.\n")
	printInstallFailure(&sbOutput, err)
	got := installShFailureTailIn(t, installDir, rerun, sbOutput.String(), 78)

	for _, want := range []string{
		"the install state could not be determined safely",
		"nothing was changed",
		"Run the same install command again: " + rerun,
		"If it stops again, send this file to StatBus support: " + bundlePath,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("operator output missing %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "Correct the settings") {
		t.Errorf("operator output blamed the settings for a non-proven-outage detection failure:\n%s", got)
	}
	// Negative: Ville's raw psql line must never reach the operator verbatim
	// — only the fixed, product-authored sentence may cross this boundary.
	if strings.Contains(got, villeRawLine) || strings.Contains(got, "shutting down") {
		t.Errorf("raw probe diagnostic leaked to the operator:\n%s", got)
	}
}

// TestDetectBundleGlobRejectsHostileExistingFile: install.sh's support-bundle
// case pattern must reject an EXISTING file whose name fits the old, looser
// glob (support-bundle-[0-9]*-[0-9]*.txt, which lets `*` absorb arbitrary
// text including spaces and injected content) but not the real bundle name
// shape (support-bundle-<8 digits>-<6 digits>.txt, from
// writeDetectionSupportBundle / time.Now().UTC().Format("20060102-150405")).
// Before the STATBUS-430 review-2 fix, the `[ -f ]` check alone let this
// hostile-but-existing path through as if it were a validated bundle.
func TestDetectBundleGlobRejectsHostileExistingFile(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash"
	installDir := withRunInstallDetectionHooks(t)
	// Fits the old glob "support-bundle-[0-9]*-[0-9]*.txt" (digits, `*`,
	// digits, `*`) but not "support-bundle-<8 digits>-<6 digits>.txt".
	hostilePath := filepath.Join(installDir, "support-bundle-1 LEAKED psql: FATAL secret=hunter2 -2.txt")
	if err := os.WriteFile(hostilePath, []byte("hostile"), 0o600); err != nil {
		t.Fatal(err)
	}
	sbOutput := "the install state could not be determined safely; nothing was changed. Run the same install command again: " + rerun +
		". If it stops again, send this file to StatBus support: " + hostilePath + "\n"
	got := installShFailureTailIn(t, installDir, rerun, sbOutput, 78)
	if strings.Contains(got, hostilePath) {
		t.Errorf("hostile-named existing file passed the support-bundle case pattern:\n%s", got)
	}
	if strings.Contains(got, "LEAKED") || strings.Contains(got, "hunter2") || strings.Contains(got, "shutting down") {
		t.Errorf("hostile file name's payload leaked into operator output:\n%s", got)
	}
}

// TestExit78AllowlistRejectsSuffixInjection: a hostile process that can write
// to install_output (or a bug that appends extra text after a legitimate
// sentence) must not get anything beyond the fixed allowlisted sentence
// through install.sh's exit-78 branch. Each case pairs a real allowlisted
// prefix with injected trailing text; before the STATBUS-430 review fix the
// bucket regex was prefix-only and let all of these through verbatim.
func TestExit78AllowlistRejectsSuffixInjection(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash"
	injections := []string{
		"port 80 is in use by nginx. Free the port with sudo systemctl disable --now nginx. Your answers are saved. Then run the same install command again: " + rerun + " EXTRA $(id) secret=hunter2",
		"Only 4 GB free on /var/lib/docker. StatBus needs at least 20 GB to install. Free some space, then run the same install command again: " + rerun + " ; rm -rf /",
		"a restart is still running. Wait for it to finish, then run the same install command again: " + rerun + " FATAL: the database system is shutting down",
		"the install state could not be determined safely; nothing was changed. Run the same install command again: " + rerun + ". If it stops again, send this file to StatBus support: /tmp/../../etc/passwd",
	}
	for _, line := range injections {
		t.Run(line, func(t *testing.T) {
			got := installShFailureTail(t, line+"\n", 78)
			if strings.Contains(got, "EXTRA") || strings.Contains(got, "rm -rf") ||
				strings.Contains(got, "shutting down") || strings.Contains(got, "/etc/passwd") {
				t.Errorf("suffix injection crossed the install-log boundary:\n%s", got)
			}
		})
	}
}
