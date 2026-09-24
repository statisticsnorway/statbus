package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
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
	if err := os.WriteFile(filepath.Join(installDir, ".env.config"), []byte("CADDY_DEPLOYMENT_MODE=development\n"), 0o600); err != nil {
		t.Fatal(err)
	}

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

func TestRunInstallStopsBeforeStepsWhenDatabaseAnswerCannotBeClassified(t *testing.T) {
	installDir := withRunInstallDetectionHooks(t)
	bundlePath := filepath.Join(installDir, "support-bundle-test.txt")
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		return 0, nil, &install.UnclassifiableResponseError{Message: `unexpected schema probe output: "junk|junk"`}
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
		"the database answered, but its install state could not be determined",
		"nothing was changed",
		"run the same install command again; if it stops here again, send this file to StatBus support: " + bundlePath,
	} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error missing %q:\n%s", want, err)
		}
	}
	if _, statErr := os.Stat(bundlePath); statErr != nil {
		t.Fatalf("support bundle was not written: %v", statErr)
	}
}

func TestRunInstallKeepsUnavailableProbeStepTableFallback(t *testing.T) {
	_ = withRunInstallDetectionHooks(t)
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		return 0, nil, errors.New("check public.upgrade existence: database connection unavailable")
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
