package upgrade

import (
	"strings"
	"testing"
)

func TestRollbackFinishingPhaseIsTargetBinaryRecovery(t *testing.T) {
	flag := &UpgradeFlag{Holder: HolderService, CommitSHA: "abc", Phase: PhaseRollbackFinishing}
	if !flag.IsServiceNewSbRecovery() {
		t.Fatal("rollback_finishing must preserve the target recovery binary")
	}
}

func TestRollbackFinishingMarkerFollowsPendingCommitAndPrecedesCleanup(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) restoreAndFinalize(")
	pending := strings.Index(body, "rollback_finish_pending_at = now()")
	phase := strings.Index(body, "PhaseRollbackFinishing")
	finalize := strings.Index(body, "d.finalizePendingRollback(")
	publish := strings.LastIndex(body, "d.restoreBinary(")
	if pending < 0 || phase < pending || finalize < phase || publish < finalize {
		t.Fatalf("rollback finishing order must be pending < cleanup marker < final row/marker < binary publish, got %d < %d < %d < %d", pending, phase, finalize, publish)
	}
}

func TestFinalizePendingRollbackCommitsBeforeMarkerRemoval(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) finalizePendingRollback(")
	commit := strings.Index(body, "tx.Commit(ctx)")
	clear := strings.Index(body, "d.clearRollbackFinishFlag(id)")
	if commit < 0 || clear < 0 || commit > clear {
		t.Fatalf("final row must commit before cleanup marker removal: commit=%d clear=%d", commit, clear)
	}
}

func TestOldBinaryAdditiveRollbackSchemaCompatibilityIsPinned(t *testing.T) {
	source := readUpgradeServiceSource(t)
	for _, fact := range []string{
		"rollback_finish_pending_at",
		"RETURNING to_jsonb(upgrade.*)",
		"PhaseRollbackFinishing",
		"20260903205636",
	} {
		if !strings.Contains(source, fact) {
			t.Errorf("old-binary additive-schema compatibility assertion missing %q", fact)
		}
	}
}
