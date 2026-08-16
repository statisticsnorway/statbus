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

// TestExecuteUpgrade_BackupPathRecordedAtCommit_STATBUS197 is oracle O2 (AC#3): inside
// executeUpgrade, the restore identity (backup_path) is recorded ONLY at the snapshot commit —
// no `SET backup_path` write may precede the backupDatabase call. RED before C1 (the early
// intent-write at the old :5428 preceded the backup). Source-order pin.
func TestExecuteUpgrade_BackupPathRecordedAtCommit_STATBUS197(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) executeUpgrade(")

	backupIdx := strings.Index(body, "d.backupDatabase(progress, backupStamp)")
	if backupIdx < 0 {
		t.Fatal("could not locate the backupDatabase call in executeUpgrade")
	}
	writeIdx := strings.Index(body, "SET backup_path = $")
	if writeIdx < 0 {
		t.Fatal("STATBUS-197 C1: executeUpgrade must record backup_path at the commit moment — no `SET backup_path` write found at all")
	}
	if writeIdx < backupIdx {
		t.Errorf("STATBUS-197 C1/O2: a `SET backup_path` write @%d PRECEDES backupDatabase @%d — identity must be recorded only AT the snapshot commit, never as early intent (a flag-lost heal in the [record→snapshot] span would restore a PRIOR attempt's snapshot)", writeIdx, backupIdx)
	}
	// The commit-moment write rides the teardown-immune primitive (queryConn is closed + the
	// read-only window is engaged there), and the flag is stamped in the same breath.
	if !strings.Contains(body[backupIdx:], "d.terminalExec(\"UPDATE public.upgrade SET backup_path") {
		t.Error("STATBUS-197 C1: the commit-moment row write must use the teardown-immune terminalExec (queryConn is closed for the consistent backup)")
	}
	if !strings.Contains(body[backupIdx:], "d.mutateHeldFlag(") {
		t.Error("STATBUS-197 C1: the flag's BackupPath must be stamped at commit too (mutateHeldFlag), so \"\"⇔nothing-moved holds in the flag carrier")
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
