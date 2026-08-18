package cmd

// STATBUS-229 oracles for the un-park's completed-retreat handling.
//
// The defect: STATBUS-210 recorded "this box retreated to source" by BLANKING the
// flag's Phase to PhaseOldSbUpgrading — a value that already means "died before
// the swap". recoverFromFlag's PreSwap branch rolls back UNCONDITIONALLY, so the
// un-park granted a fresh attempt and the next step rolled it back, which is the
// collision 210 existed to prevent.
//
// The fix: the retreat is recorded in its own field, and the un-park REMOVES the
// whole flag when it is set — after a completed retreat nothing is in flight, so
// the scheduled row is claimed fresh through the normal path.
//
// The conditional is load-bearing. An era-REFUSED park leaves the marker unset,
// and its flag truthfully describes a mid-upgrade box that RecoverFromFlag must
// still handle. The arms below pin BOTH outcomes, because collapsing them into
// one was 210's defect.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// retreatFixture writes a service-held flag, optionally carrying the completed
// retreat marker, and returns the project dir.
func retreatFixture(t *testing.T, retreated bool) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	flag := upgrade.UpgradeFlag{
		ID:         7,
		CommitSHA:  "0123456789abcdef0123456789abcdef01234567",
		StartedAt:  time.Now(),
		InvokedBy:  "scheduled",
		Trigger:    "scheduled",
		Holder:     upgrade.HolderService,
		Phase:      upgrade.PhaseNewSbSwapped,
		BackupPath: "/home/statbus/statbus-backups/pre-upgrade-active",
		Step:       "image-pull",
	}
	if retreated {
		at := time.Now()
		flag.RetreatedToSourceAt = &at
	}
	data, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "tmp", "upgrade-in-progress.json"), data, 0644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func flagOnDisk(t *testing.T, dir string) *upgrade.UpgradeFlag {
	t.Helper()
	flag, err := upgrade.ReadFlagFile(dir)
	if err != nil {
		t.Fatalf("ReadFlagFile: %v", err)
	}
	return flag
}

// TestRemoveFlagAfterRetreat_RemovesOnlyAMarkedFlag_STATBUS229 is the RED-first
// behavioural core. RED against current code: RemoveFlagAfterRetreat does not
// exist, and nothing removes the flag at the un-park — which is why the granted
// attempt is rolled back instead of run.
func TestRemoveFlagAfterRetreat_RemovesOnlyAMarkedFlag_STATBUS229(t *testing.T) {
	t.Run("marked flag: removed, so the row is claimed fresh", func(t *testing.T) {
		dir := retreatFixture(t, true)
		svc := upgrade.NewService(dir, false, "", "")

		if err := svc.RemoveFlagAfterRetreat(); err != nil {
			t.Fatalf("a completed-retreat flag must be removable: %v", err)
		}
		if flag := flagOnDisk(t, dir); flag != nil {
			t.Error("the flag survived: after a completed retreat nothing is in flight, and a surviving flag sends the un-parked attempt into crash recovery — which rolls it back (STATBUS-229)")
		}
	})

	t.Run("UNMARKED flag: refused, because an era-refused park is still mid-upgrade", func(t *testing.T) {
		dir := retreatFixture(t, false)
		svc := upgrade.NewService(dir, false, "", "")

		err := svc.RemoveFlagAfterRetreat()
		if err == nil {
			t.Fatal("removing an UNMARKED flag must be refused. A park whose restoration was REFUSED leaves the marker unset and its flag truthfully describes a genuinely mid-upgrade box — removing it strands exactly the state RecoverFromFlag exists to handle. The two park outcomes must stay distinguishable; collapsing them was 210's defect")
		}
		if !strings.Contains(err.Error(), "no completed-retreat marker") {
			t.Errorf("the refusal must name the missing marker so the caller knows which park outcome it is looking at, got: %v", err)
		}
		if flag := flagOnDisk(t, dir); flag == nil {
			t.Error("the unmarked flag was removed anyway — the refusal must be effective, not advisory")
		}
	})
}

// TestUnparkRemovesFlagOnlyWhenRetreated_STATBUS229 pins the CALL SITE: the
// removal is conditional, sits beside ClearFlagStepHistory, and runs after the
// successful un-park but before RecoverFromFlag. The ordering is the fix — a
// removal any earlier would delete the very flag through which `./sb install`
// discovers the parked box.
func TestUnparkRemovesFlagOnlyWhenRetreated_STATBUS229(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install_upgrade.go"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(src)

	unparkIdx := strings.Index(text, "UN-PARKED upgrade id=")
	if unparkIdx < 0 {
		t.Fatal("could not locate the un-park announcement — re-anchor this pin")
	}
	removeIdx := strings.Index(text, "RemoveFlagAfterRetreat()")
	if removeIdx < 0 {
		t.Fatal("STATBUS-229: the un-park must remove the flag of an attempt that already retreated to source — otherwise RecoverFromFlag reads it as an in-flight upgrade and rolls the granted attempt back")
	}
	if removeIdx < unparkIdx {
		t.Error("STATBUS-229: the removal must come AFTER the successful un-park — the flag is how ./sb install discovers the parked box in the first place")
	}
	recoverIdx := strings.Index(text, "RecoverFromFlag(")
	if recoverIdx >= 0 && removeIdx > recoverIdx {
		t.Error("STATBUS-229: the removal must come BEFORE RecoverFromFlag — that ordering IS the fix; afterwards, recovery has already rolled the attempt back")
	}

	// CONDITIONAL, and the guard must be the marker — not something weaker.
	if !strings.Contains(text, "flag.HasRetreatedToSource()") {
		t.Error("STATBUS-229: the removal must be guarded by the completed-retreat marker. Unconditional removal strands an era-REFUSED park, whose flag truthfully describes a mid-upgrade box")
	}
	// The unmarked branch must still clear the death history (STATBUS-044 #6).
	if !strings.Contains(text, "ClearFlagStepHistory()") {
		t.Error("STATBUS-229 must not drop STATBUS-044's step-history clearing for the unmarked (era-refused) park — that path still grants one fresh attempt and would otherwise insta-re-park")
	}
}
