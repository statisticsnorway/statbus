package upgrade

import (
	"os"
	"strings"
	"testing"
)

func TestRollbackDirectionStampIsAtCommonEntryBeforeDestructiveWork(t *testing.T) {
	source, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	body := extractFuncBody(t, string(source), "func (d *Service) rollback(")
	stamp := strings.Index(body, "d.recordRollbackCommit()")
	stop := strings.Index(body, `runCommand(projDir, "docker"`)
	restore := strings.Index(body, "d.restoreDatabase(")
	if stamp < 0 || stop < 0 || restore < 0 {
		t.Fatalf("rollback structural anchors missing: stamp=%d stop=%d restore=%d", stamp, stop, restore)
	}
	if stamp > stop || stamp > restore {
		t.Fatalf("rollback direction must be durable before destructive work: stamp=%d stop=%d restore=%d", stamp, stop, restore)
	}
}

func TestEveryRollbackEntryUsesExactlyOneCommonStamp(t *testing.T) {
	source, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(source)
	tests := []struct {
		name string
		sig  string
		want int
	}{
		{name: "common rollback entry including in-process failure", sig: "func (d *Service) rollback(", want: 1},
		{name: "recovery wrapper does not double stamp", sig: "func (d *Service) recoveryRollback(", want: 0},
		{name: "flagless observed-state route does not double stamp", sig: "func (d *Service) completeInProgressUpgrade(", want: 0},
		{name: "in-process failure routes through common rollback", sig: "func (d *Service) newSbUpgradingFailure(", want: 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			body := extractFuncBody(t, src, tt.sig)
			if got := strings.Count(body, "d.recordRollbackCommit()"); got != tt.want {
				t.Fatalf("%s has %d rollback stamps, want %d", tt.sig, got, tt.want)
			}
			if tt.sig == "func (d *Service) newSbUpgradingFailure(" && !strings.Contains(body, "d.rollback(") {
				t.Fatal("in-process newSbUpgradingFailure no longer reaches the common rollback entry")
			}
		})
	}
}

func TestRecoverFromFlagRollbackMarkerWinsBeforeObservedState(t *testing.T) {
	source, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(source)
	body := extractFuncBody(t, src, "func (d *Service) recoverFromFlag(")
	durable := strings.Index(body, "flag.Step == StepRollback")
	observed := strings.Index(body, "d.verifyUpgradeObservedStateEx(")
	if durable < 0 || observed < 0 || durable > observed {
		t.Fatalf("durable rollback routing must precede observed-state routing: rollback=%d observed=%d", durable, observed)
	}
	wrapper := extractFuncBody(t, src, "func (d *Service) recoveryRollback(")
	for _, required := range []string{"acquireRecoveryFlock(d.projDir, flag)", "rollbackResumeIsTerminal(flag.Step, flag.PriorDeathStep)", "d.rollback("} {
		if !strings.Contains(wrapper, required) {
			t.Fatalf("held/revalidated rollback route lost %q", required)
		}
	}
}

func TestRecordRollbackCommitRollsHistoryExactlyOnce(t *testing.T) {
	dir := t.TempDir()
	seed := UpgradeFlag{ID: 354, CommitSHA: "abc123", Holder: HolderService, Phase: PhaseNewSbUpgrading, Step: StepMigrateUp, PriorDeathStep: StepConfigGenerate}
	lock, err := acquireFlock(dir, seed)
	if err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: dir, flagLock: lock}
	d.recordRollbackCommit()
	d.flagLock = nil
	lock.Close()
	got, err := ReadFlagFile(dir)
	if err != nil || got == nil {
		t.Fatalf("read stamped flag: got=%v err=%v", got, err)
	}
	if got.Step != StepRollback || got.PriorDeathStep != StepMigrateUp {
		t.Fatalf("rollback history did not roll exactly once: step=%q prior=%q", got.Step, got.PriorDeathStep)
	}
}
