package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// An install interrupted by Ctrl-C (or a dropped ssh session) leaves its own
// marker, tmp/upgrade-in-progress.json with holder "install", and no process
// holding it. That is the install's mutex, not an upgrade: nothing was being
// upgraded, and on a first install no container or database may exist yet
// (the manual box, rc.09: Ctrl-C at step 10, then every rerun stopped with
// "the web server (proxy) container was removed while an upgrade was
// interrupted"). Running the same install command again must clear the marker
// and continue, without needing a database, containers or an outside fix.
func TestCrashRecoveryClearsAnInterruptedInstallsMarkerWithoutADatabase(t *testing.T) {
	dir := t.TempDir()
	for name, body := range map[string]string{
		".env.config":      "CADDY_DEPLOYMENT_MODE=standalone\n",
		".env.credentials": "POSTGRES_ADMIN_PASSWORD=x\n",
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	// No docker on PATH: recovery must not need one for this marker.
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\necho \"docker must not be called: $*\" >&2\nexit 97\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	lock, err := upgrade.AcquireInstallFlag(dir, "operator:statbus")
	if err != nil {
		t.Fatal(err)
	}
	lock.Close() // Ctrl-C: the process is gone, the marker stays.

	var restart func()
	out := captureStdout(t, func() {
		if err := runCrashRecovery(dir, &restart); err != nil {
			t.Fatalf("recovery of an interrupted install failed: %v", err)
		}
	})
	if _, statErr := os.Stat(filepath.Join(dir, "tmp", "upgrade-in-progress.json")); !os.IsNotExist(statErr) {
		t.Fatalf("the interrupted install's marker is still there: %v", statErr)
	}
	if !strings.Contains(out, "The previous install was interrupted; continuing it.") {
		t.Fatalf("output = %q, want the continuation line", out)
	}
	if strings.Contains(out, "proxy") || strings.Contains(out, "upgrade") {
		t.Fatalf("an interrupted install was described as an upgrade problem:\n%s", out)
	}
}

// After an interrupted first install's marker is cleared, the installer looks
// at the box again. With no database container yet (Ctrl-C before Services)
// that look finds no database, exactly as the first look of a fresh install
// does, and the same run continues with the steps. The manual box, rc.10:
// "The previous install was interrupted; continuing it." was followed by
// "the installer could not finish" (re-detect: database unavailable), and only
// a second run continued.
func TestInterruptedInstallContinuesInTheSameRunWhenNoDatabaseExists(t *testing.T) {
	dir := withRunInstallDetectionHooks(t)
	probes := 0
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		probes++
		if probes == 1 {
			return install.StateCrashedUpgrade, &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: upgrade.HolderInstall, Trigger: "install"}}, nil
		}
		return 0, nil, fmt.Errorf("probe database reachability: %w", install.ErrDatabaseUnavailable)
	}
	recoverCrashedInstall = func(string, *func()) error { return nil }
	checkInstallSigners = func(string) bool { return true }
	steps := 0
	runInstallStepTableTestHook = func() error { steps++; return nil }
	_ = dir

	out := captureStdout(t, func() {
		if err := runInstall(); err != nil {
			t.Fatalf("the interrupted install did not continue in the same run: %v", err)
		}
	})
	if steps != 1 {
		t.Fatalf("step table ran %d times, want 1:\n%s", steps, out)
	}
	if !strings.Contains(out, "No StatBus database is running yet; continuing with the installation.") {
		t.Fatalf("output = %q, want the no-database continuation line", out)
	}
}
