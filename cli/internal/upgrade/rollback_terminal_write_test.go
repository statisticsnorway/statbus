package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/invariants"
)

// Guards rollback()'s terminal-state write. The bug the overnight
// campaign found (scenario 2-preswap-backup-kill, preswap-backup-kill on real systemd): rollback()
// restarts the DB and races its own reconnect; the two terminal UPDATEs were
// single-shot and silently swallowed failure, then removeUpgradeFlag() ran
// UNCONDITIONALLY and the process exited claiming success — row stuck
// in_progress, flag breadcrumb destroyed. Full trace:
// tmp/plans/scenario21-rollback-terminal-write-verdict.md.
//
// The fix: writeRollbackTerminal retries (bounded) + fails LOUD on exhaustion
// (markTerminal) + the caller removes the flag ONLY on a landed write, KEEPING
// it on failure so the next boot's recoverFromFlag / completeInProgressUpgrade
// reconciles the row.

// TestWriteRollbackTerminal_ExhaustionMarksTerminalAndKeepsFlag is the
// DB-independent behavioral guard. With no .env in projDir, reconnect() fails
// fast every attempt, so the bounded retry exhausts deterministically. The
// helper MUST: (a) return false (the write never landed), (b) leave the flag
// file in place (the helper itself must never remove it — the caller owns the
// conditional removal), and (c) name the failure on the on-disk audit channel
// (install-terminal.txt) rather than swallow it.
//
// The happy path (write lands → caller removes the flag) requires a live DB and
// is covered by the install-recovery harness (scenario 2-preswap-backup-kill) on the Hetzner box —
// the same split as the other terminal-write sites, which are not unit-tested
// against a live queryConn (see ground_truth_test.go's t.Skip).
func TestWriteRollbackTerminal_ExhaustionMarksTerminalAndKeepsFlag(t *testing.T) {
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0o755); err != nil {
		t.Fatal(err)
	}

	d := &Service{projDir: projDir}
	// Write a flag so we can prove the helper does NOT remove it on failure.
	if err := d.writeUpgradeFlag(7, "deadbeefdeadbeef", []string{"v0.0.0-test"}, "test", string(TriggerService), false); err != nil {
		t.Fatalf("writeUpgradeFlag: %v", err)
	}
	flagPath := d.flagPath()
	if _, err := os.Stat(flagPath); err != nil {
		t.Fatalf("precondition: flag file should exist after writeUpgradeFlag; stat err=%v", err)
	}

	// No .env in projDir → reconnect()/connect() fails fast each attempt → the
	// bounded retry exhausts (≈1.6s of backoff) without ever reaching a DB.
	ok := d.writeRollbackTerminal(context.Background(), 7,
		"UPDATE public.upgrade SET state = 'rolled_back', error = $1, rolled_back_at = now() WHERE id = $2"+upgradeRowReturning,
		"some rollback reason", LabelRolledBackNormal)

	if ok {
		t.Fatalf("writeRollbackTerminal must return false when the DB is unreachable")
	}
	// The flag MUST remain — it is the breadcrumb the next boot reconciles from.
	if _, err := os.Stat(flagPath); err != nil {
		t.Errorf("flag file must REMAIN after a failed terminal write (breadcrumb for next-boot recovery); stat err=%v", err)
	}
	// The named invariant must be on the on-disk audit channel — loud, not swallowed.
	got := invariants.ReadTerminal(projDir)
	if !strings.Contains(got, "ROLLBACK_TERMINAL_WRITE_FAILED") {
		t.Errorf("expected ROLLBACK_TERMINAL_WRITE_FAILED in install-terminal.txt; got: %q", got)
	}

	d.removeUpgradeFlag() // cleanup: release the flock held by writeUpgradeFlag
}

// TestRollbackTerminalWrite_StructuralContract pins the source-level shape the
// architect reviews hardest: the helper reuses the shared retry primitives
// (not a hand-rolled loop), never touches the flag itself, and rollback()
// guards BOTH flag removals behind a landed terminal write. Mirrors the
// source-structure guards in postswap_test.go / resume_start_phase_test.go.
func TestRollbackTerminalWrite_StructuralContract(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	source := string(src)

	helper := extractFuncBody(t, source, "func (d *Service) writeRollbackTerminal(")
	for _, want := range []string{"retryBackoff(", "isConnError(", "d.reconnect(", "d.markTerminal("} {
		if !strings.Contains(helper, want) {
			t.Errorf("writeRollbackTerminal must reuse %q (no hand-rolled loop / silent swallow); not found in body", want)
		}
	}
	// The helper must NOT remove the flag — the caller owns the conditional
	// removal so the flag is KEPT on failure. (Comments are stripped by
	// extractFuncBody, so this matches code only.)
	if strings.Contains(helper, "removeUpgradeFlag") {
		t.Errorf("writeRollbackTerminal must NOT call removeUpgradeFlag — flag retention is the caller's conditional, so the breadcrumb survives a failed write")
	}

	// STATBUS-111: the restore-through-terminal-write TAIL (the degraded `failed`
	// tier + the `rolled_back` tier) was extracted from rollback() into
	// restoreAndFinalize (PIN 1). The catastrophic git-restore-ABORT `failed`
	// stays in rollback() (it precedes the extraction boundary). The 3-write /
	// guarded-removal invariant is unchanged — it now holds across the rollback
	// PATH = rollback() + restoreAndFinalize, so scan both.
	rbPath := extractFuncBody(t, source, "func (d *Service) rollback(") + "\n" +
		extractFuncBody(t, source, "func (d *Service) restoreAndFinalize(")
	// ALL THREE terminal writes route through the helper: the catastrophic
	// git-restore-abort `failed` (in rollback), the degraded `failed`, and the
	// `rolled_back` tier (both in restoreAndFinalize). (The abort path is the
	// same bug class — single-shot swallow + unconditional removeUpgradeFlag
	// before os.Exit — so it gets the same fix.)
	if n := strings.Count(rbPath, "d.writeRollbackTerminal("); n != 3 {
		t.Errorf("rollback path (rollback + restoreAndFinalize) must call writeRollbackTerminal exactly 3× (abort-failed + degraded-failed + rolled_back); got %d", n)
	}
	// Every flag removal is guarded by a landed terminal write: the count of
	// `if d.writeRollbackTerminal(` guards equals the count of removeUpgradeFlag()
	// calls, and both equal 3 — no unconditional removal survives.
	removes := strings.Count(rbPath, "d.removeUpgradeFlag()")
	guards := strings.Count(rbPath, "if d.writeRollbackTerminal(")
	if removes != 3 || guards != 3 {
		t.Errorf("flag-removal symmetry: want 3 removeUpgradeFlag() each guarded by `if d.writeRollbackTerminal(`; got removes=%d guards=%d", removes, guards)
	}
	// The old single-shot swallow must be gone from every tier.
	for _, gone := range []string{"Scan(&failedJSON)", "Scan(&rollbackJSON)", "Scan(&abortJSON)"} {
		if strings.Contains(rbPath, gone) {
			t.Errorf("rollback path still contains the single-shot swallow %q — it must route through writeRollbackTerminal", gone)
		}
	}
}
