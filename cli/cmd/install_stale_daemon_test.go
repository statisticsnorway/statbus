package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// STATBUS-382: an active upgrade daemon whose running program is not the ./sb
// this install leaves on disk is restarted at install exit, so the next claim
// runs the installed code.
func TestStaleUpgradeDaemonIsRestartedAtInstallExit(t *testing.T) {
	dir := t.TempDir()
	disk := filepath.Join(dir, "sb")
	if err := os.WriteFile(disk, []byte("sb v2"), 0o755); err != nil {
		t.Fatal(err)
	}
	same := filepath.Join(dir, "running-same")
	if err := os.WriteFile(same, []byte("sb v2"), 0o755); err != nil {
		t.Fatal(err)
	}
	older := filepath.Join(dir, "running-older")
	if err := os.WriteFile(older, []byte("sb v1"), 0o755); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		name    string
		daemon  runningDaemon
		fixup   bool
		want    upgradeDaemonFinalAction
		wantWhy string
	}{
		{"running the installed program", runningDaemon{active: true, exe: same}, false, upgradeDaemonNoAction, ""},
		{"running an older program", runningDaemon{active: true, exe: older}, false, upgradeDaemonRestart, "is running a different program than " + disk},
		{"running a deleted program", runningDaemon{active: true, exe: older, exeDeleted: true}, false, upgradeDaemonRestart, "is running a program that was replaced on disk"},
		{"not running", runningDaemon{active: false}, false, upgradeDaemonNoAction, ""},
		{"inside the daemon's own post-upgrade fixup", runningDaemon{active: true, exe: older}, true, upgradeDaemonNoAction, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, why := staleDaemonFinalAction(c.daemon, disk, c.fixup)
			if got != c.want {
				t.Fatalf("action = %q, want %q (why %q)", got, c.want, why)
			}
			if why != c.wantWhy {
				t.Fatalf("why = %q, want %q", why, c.wantWhy)
			}
		})
	}
}
