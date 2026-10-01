package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestServiceFailureWithJournal(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "journalctl")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nprintf '%s\\n' \"$*\"\nprintf '%s\\n' 'service root cause'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, tc := range []struct {
		name string
		user bool
		want string
	}{{"user", true, "--user -u statbus-upgrade@statbus.service -n 40 --no-pager"}, {"system", false, "-u statbus-upgrade@statbus.service -n 40 --no-pager"}} {
		t.Run(tc.name, func(t *testing.T) {
			cause := errors.New("start timed out")
			err := serviceFailureWithJournal("enable service", "statbus-upgrade@statbus.service", tc.user, cause)
			if !errors.Is(err, cause) || !strings.Contains(err.Error(), tc.want) || !strings.Contains(err.Error(), "service root cause") {
				t.Fatalf("missing journal or cause: %v", err)
			}
		})
	}
}

// Review round 2: the final drifted-unit restart dispatch must also surface
// the journal, not only enable/reset-failed.
func TestReconcileRestartUsesJournalHelper_STATBUS422(t *testing.T) {
	src, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	start := strings.Index(string(src), "var dispatchUpgradeDaemonFinalAction")
	if start < 0 {
		t.Fatal("reconcile-restart branch not found")
	}
	window := string(src)[start : start+900]
	if !strings.Contains(window, `"--user", "--no-block", string(action), instance`) {
		t.Fatal("nonblocking final lifecycle invocation missing")
	}
	if !strings.Contains(window, `serviceFailureWithJournal(string(action)+" service", instance, true, err)`) {
		t.Fatal("final lifecycle failure must go through serviceFailureWithJournal")
	}
	if strings.Contains(window, "fmt.Errorf(\"restart %s after unit reconcile") {
		t.Fatal("stale journal-less restart error remains")
	}
}
