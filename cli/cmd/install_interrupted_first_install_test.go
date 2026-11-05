package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

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
