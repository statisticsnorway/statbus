package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// narrowRefspecRepo builds a temp git repo in the narrow-clone state
// (STATBUS-325 defect 1): only a tag pin, no wildcard — so normalization has
// visible work to do.
func narrowRefspecRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	run := func(args ...string) {
		t.Helper()
		c := exec.Command("git", testgit.Args(args...)...)
		c.Dir = dir
		c.Env = testgit.Env()
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("git %s: %v (%s)", strings.Join(args, " "), err, out)
		}
	}
	run("init", "-q", "--initial-branch=master", ".")
	run("remote", "add", "origin", "https://example.invalid/statbus.git")
	unset := exec.Command("git", testgit.Args("config", "--unset-all", "remote.origin.fetch")...)
	unset.Dir = dir
	unset.Env = testgit.Env()
	_ = unset.Run()
	run("config", "--add", "remote.origin.fetch", "+refs/tags/v2026.08.0-rc.16:refs/tags/v2026.08.0-rc.16")
	return dir
}

func fetchRefspecs(t *testing.T, dir string) []string {
	t.Helper()
	c := exec.Command("git", testgit.Args("config", "--get-all", "remote.origin.fetch")...)
	c.Dir = dir
	c.Env = testgit.Env()
	out, err := c.Output()
	if err != nil {
		return nil
	}
	var got []string
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			got = append(got, l)
		}
	}
	return got
}

// STATBUS-530 (527 review, B1): refspec normalization is housekeeping and must
// never take ownership of upgrade recovery state. With a crashed or parked
// upgrade's service marker on disk (flock free), the refspec path must REFUSE
// the mutex, leave the marker byte-identical, and leave it readable for the
// next `./sb install` to recover from. Before the fix this path used
// AcquireInstallFlag + ReleaseInstallFlag, which overwrote the marker and then
// deleted it — the next install saw no marker and skipped recovery.
func TestRefspecNormalize_PreservesServiceRecoveryMarker(t *testing.T) {
	for _, phase := range []string{upgrade.PhaseNewSbSwapped, upgrade.PhaseNewSbUpgrading} {
		t.Run("phase="+phase, func(t *testing.T) {
			dir := narrowRefspecRepo(t)
			marker := seedServiceRecoveryMarker(t, dir, phase)

			normalizeRefspecsUnderUpgradeMutex(dir)

			markerBytesUnchanged(t, dir, marker)
			// The next ./sb install's Detect reads exactly this: a parseable
			// service-held marker it classifies as crashed-upgrade recovery.
			flag, err := upgrade.ReadFlagFile(dir)
			if err != nil {
				t.Fatalf("the next ./sb install cannot read the recovery marker: %v", err)
			}
			if flag == nil || flag.Holder != upgrade.HolderService || flag.Phase != phase || flag.BackupPath == "" {
				t.Fatalf("the next ./sb install sees %+v, want the service recovery state (holder=service phase=%s with backup)", flag, phase)
			}
			if upgrade.IsFlockHeld(dir) {
				t.Error("refspec normalization must not hold the lock after refusing")
			}
			// Housekeeping was skipped, not performed under the adopted marker.
			for _, spec := range fetchRefspecs(t, dir) {
				if strings.Contains(spec, "refs/heads/*") {
					t.Errorf("normalization ran despite the recovery marker: refspecs = %v", fetchRefspecs(t, dir))
				}
			}
		})
	}
}

// STATBUS-530: the ordinary path is unchanged. With no marker at all the
// refspec path claims the mutex, normalizes to the canonical layout, and
// releases — deleting only its own marker.
func TestRefspecNormalize_NormalizesWhenNoMarker(t *testing.T) {
	dir := narrowRefspecRepo(t)

	normalizeRefspecsUnderUpgradeMutex(dir)

	got := fetchRefspecs(t, dir)
	if len(got) != len(upgrade.CanonicalRefspecs) {
		t.Fatalf("got %d refspecs, want %d:\n  got:  %v\n  want: %v",
			len(got), len(upgrade.CanonicalRefspecs), got, upgrade.CanonicalRefspecs)
	}
	for i, want := range upgrade.CanonicalRefspecs {
		if got[i] != want {
			t.Errorf("refspec %d = %q, want %q", i, got[i], want)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "tmp", "upgrade-in-progress.json")); !os.IsNotExist(err) {
		t.Errorf("the released install marker must not remain (a stale marker would misdetect a crashed upgrade), stat err: %v", err)
	}
}
