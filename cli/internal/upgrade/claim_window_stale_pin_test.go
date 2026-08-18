package upgrade

import (
	"strings"
	"testing"
)

// TestRollback_NoTouchGuard_STATBUS197 is oracle O1 (AC#2): a rollback with backupPath=="" must
// NOT invoke restoreGitState/restoreBinary — the attempt touched nothing, so restoring
// git/binary from a predecessor's pin would move the box to a version no one asked for. Same
// source-order seam family as TestRecoveryRollback_ParkedSkipPrecedesRestore. RED before C2.
func TestRollback_NoTouchGuard_STATBUS197(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])

	// C2a: in rollback(), the git restore is reached only on the non-empty branch — the
	// `if backupPath == ""` no-touch skip guards (precedes) the restoreGitState call.
	rb := extractFuncBody(t, src, "func (d *Service) rollback(")
	guardIdx := strings.Index(rb, `if backupPath == ""`)
	gitIdx := strings.Index(rb, "d.restoreGitState(restoreTargetSHA")
	if guardIdx < 0 || gitIdx < 0 || guardIdx > gitIdx {
		t.Errorf("C2a: rollback must guard restoreGitState behind `if backupPath == \"\"` (no-touch skip @%d must precede the git restore @%d)", guardIdx, gitIdx)
	}
	// The skip branch must NOT fall into an ABORT — it keeps the box in service. The guard's
	// progress line names the principle so the operator/log reads honestly.
	if !strings.Contains(rb, "this attempt recorded no committed snapshot") {
		t.Error("C2a: the no-touch skip must announce the principle (nothing committed → nothing to restore)")
	}

	// C2b: in restoreAndFinalize(), restoreBinary is guarded by a non-empty backupPath, in the
	// SAME identity key — a no-snapshot rollback must not install a predecessor's ./sb.old.
	raf := extractFuncBody(t, src, "func (d *Service) restoreAndFinalize(")
	binIdx := strings.Index(raf, "d.restoreBinary(progress)")
	condIdx := strings.Index(raf, `if backupPath != ""`)
	if binIdx < 0 || condIdx < 0 || condIdx > binIdx {
		t.Errorf("C2b: restoreAndFinalize must guard restoreBinary behind `if backupPath != \"\"` (guard @%d must precede restoreBinary @%d)", condIdx, binIdx)
	}
}

// TestExecuteUpgrade_BackupPathNeverRecordedAsEarlyIntent_STATBUS197 is oracle O2 (AC#3),
// AMENDED BY STATBUS-228 (architect-ruled, 2026-08-18).
//
// 197's SURVIVING invariant, still pinned below: the restore identity is NEVER recorded as
// early intent — no `SET backup_path` write may precede backupDatabase. A flag-lost heal in
// the [record → snapshot] span would otherwise restore a PRIOR attempt's snapshot.
//
// What 228 changed, and why this test could not keep its original form: 197 also required
// BOTH carriers to be written at the snapshot-commit moment, in the same breath. That moment
// sits INSIDE the window where Step 4 has stopped the postgres SERVER, so the row write could
// never land (terminalExec survives our CONNECTION dying, not a stopped server) and the flag
// stamp gave a PreSwap flag a BackupPath, falsifying the PreSwap branch's no-touch premise.
// The identity is now recorded where each carrier can hold it truthfully — the FLAG at the
// swap, the ROW at the first reconnect after it. Those two moments have their own pins in
// backup_path_carriers_test.go; this test keeps 197's never-as-intent ordering rule, which
// 228 does not weaken (both new write points are still AFTER backupDatabase).
func TestExecuteUpgrade_BackupPathNeverRecordedAsEarlyIntent_STATBUS197(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) executeUpgrade(")

	backupIdx := strings.Index(body, "d.backupDatabase(progress, backupStamp)")
	if backupIdx < 0 {
		t.Fatal("could not locate the backupDatabase call in executeUpgrade")
	}
	// executeUpgrade must contain NO backup_path row write at all any more: the only
	// recorder is applyNewSbUpgrading's post-reconnect write (STATBUS-228). A write
	// appearing here again is either early intent (197's bug) or a write into the
	// server-stopped window (228's bug) — both are refused by this pin.
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			continue
		}
		if strings.Contains(trimmed, "SET backup_path = $") {
			t.Errorf("STATBUS-197 C1 / STATBUS-228: executeUpgrade must contain NO backup_path row write. Before backupDatabase it would be early intent (a flag-lost heal would restore a PRIOR attempt's snapshot); after it, the postgres SERVER is stopped and the write cannot land. The single recorder is the post-reconnect write in applyNewSbUpgrading.\n  offending line: %s", trimmed)
		}
	}
	// The FLAG's identity is stamped at the swap boundary — after the snapshot commit, so
	// 197's never-as-intent rule still holds for the carrier that survives the DB-down gap.
	stampIdx := strings.Index(body, "d.updateFlagNewSbSwapped(backupPath)")
	if stampIdx < 0 {
		t.Fatal("STATBUS-228: the flag must gain its BackupPath at the swap (updateFlagNewSbSwapped(backupPath)) — that is the carrier that works while the server is stopped")
	}
	if stampIdx < backupIdx {
		t.Errorf("STATBUS-197 C1: the flag stamp @%d PRECEDES backupDatabase @%d — the identity must never be recorded before the snapshot commits", stampIdx, backupIdx)
	}
}

// TestCompletion_DeletesRollbackBinary_STATBUS197 is oracle O3 (AC#4): ./sb.old is deleted at
// every serve-proven completion, so `sb.old exists ⇔ an unresolved swap`. RED before C3 (which
// added the deletion). Structural pin: the helper removes the .old path and is called after
// each completion log.
func TestCompletion_DeletesRollbackBinary_STATBUS197(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])

	h := extractFuncBody(t, src, "func (d *Service) deleteRollbackBinaryOnCompletion(")
	if !strings.Contains(h, `"sb") + ".old"`) || !strings.Contains(h, "os.Remove(") {
		t.Error("deleteRollbackBinaryOnCompletion must os.Remove the ./sb.old path")
	}
	if !strings.Contains(h, "os.IsNotExist(err)") {
		t.Error("deleteRollbackBinaryOnCompletion must treat a missing .old (first-ever upgrade) as the normal case, not an error")
	}

	// Called at ALL THREE serve-proven completions — each resolves a real swap.
	for _, label := range []string{"LabelCompletedNormal", "LabelCompletedFromInProgress", "LabelCompletedSelfHeal"} {
		logIdx := strings.Index(src, "logUpgradeRow("+label)
		if logIdx < 0 {
			t.Errorf("completion label %s not found", label)
			continue
		}
		window := src[logIdx:]
		if end := 240; len(window) > end {
			window = window[:end]
		}
		if !strings.Contains(window, "d.deleteRollbackBinaryOnCompletion()") {
			t.Errorf("STATBUS-197 C3: deleteRollbackBinaryOnCompletion must be called right after logUpgradeRow(%s) — every serve-proven completion resolves a swap; a stale .old there would defeat the invariant", label)
		}
	}
}
