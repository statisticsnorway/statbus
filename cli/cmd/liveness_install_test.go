package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// Liveness install reconcile (plan piece #7). The paired observer units
// (statbus-upgrade-liveness@.service + .timer) are copied VERBATIM to
// ~/.config/systemd/user/, so livenessUnitsMatchRepo is the byte-compare drift
// check — both files must match the repo templates, mirroring unitFileMatchesRepo
// for the upgrade unit. checkLivenessUnitsDone ANDs this with `timer is-active`
// (the is-active half needs real systemd → Hetzner harness, not here).

// writeLivenessFixture lays out a temp repo with both ops/ liveness unit files
// and points $HOME at a temp dir with the user systemd dir created. Returns
// (dir, userServiceDir).
func writeLivenessFixture(t *testing.T, svc, timer string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	opsDir := filepath.Join(dir, "ops")
	if err := os.MkdirAll(opsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(opsDir, "statbus-upgrade-liveness@.service"), []byte(svc), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(opsDir, "statbus-upgrade-liveness@.timer"), []byte(timer), 0o644); err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	userServiceDir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(userServiceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	return dir, userServiceDir
}

func TestLivenessUnitsMatchRepo_BothIdenticalIsMatch(t *testing.T) {
	svc := "[Unit]\nDescription=liveness svc\n[Service]\nType=oneshot\n"
	timer := "[Timer]\nOnUnitActiveSec=5min\n"
	dir, userDir := writeLivenessFixture(t, svc, timer)
	if err := os.WriteFile(filepath.Join(userDir, "statbus-upgrade-liveness@.service"), []byte(svc), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(userDir, "statbus-upgrade-liveness@.timer"), []byte(timer), 0o644); err != nil {
		t.Fatal(err)
	}
	if !livenessUnitsMatchRepo(dir) {
		t.Error("both on-disk liveness units byte-identical to repo must MATCH (no reconcile)")
	}
}

func TestLivenessUnitsMatchRepo_TimerDriftIsMismatch(t *testing.T) {
	svc := "[Unit]\nDescription=liveness svc\n[Service]\nType=oneshot\n"
	timer := "[Timer]\nOnUnitActiveSec=5min\n"
	dir, userDir := writeLivenessFixture(t, svc, timer)
	// service matches, timer drifted (e.g. old 10min cadence) → mismatch.
	if err := os.WriteFile(filepath.Join(userDir, "statbus-upgrade-liveness@.service"), []byte(svc), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(userDir, "statbus-upgrade-liveness@.timer"), []byte("[Timer]\nOnUnitActiveSec=10min\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if livenessUnitsMatchRepo(dir) {
		t.Error("a drifted timer (10min vs repo 5min) must be a MISMATCH so install reconciles it")
	}
}

func TestLivenessUnitsMatchRepo_MissingIsMismatch(t *testing.T) {
	// Fresh box: ops/ has both files, user dir has neither → mismatch.
	dir, _ := writeLivenessFixture(t, "[Unit]\nx\n", "[Timer]\ny\n")
	if livenessUnitsMatchRepo(dir) {
		t.Error("missing on-disk liveness units must be a MISMATCH (fresh install must write them)")
	}
}
