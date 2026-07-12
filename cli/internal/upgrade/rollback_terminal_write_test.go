package upgrade

import (
	"context"
	"errors"
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

	// No .env in projDir → terminalUpdate's recoveryDSN fails fast each attempt →
	// the bounded retry exhausts (≈1.6s of backoff) without ever reaching a DB.
	// STATBUS-154: writeRollbackTerminal no longer takes the pass ctx (the
	// teardown-immune terminalUpdate makes its own context.Background).
	ok := d.writeRollbackTerminal(7,
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

	// STATBUS-154/-163: the teardown-immune retry/reconnect/exemption core lives in
	// ONE definition, terminalConnDo; terminalUpdate (row writes) and terminalExec
	// (window flips) are thin wrappers. The pin is a contract on the PROPERTY, not
	// on which function's lines carry it (163's closing lesson — one core, no
	// hand-synced copies to drift). Pin the core + both wrappers' delegation.
	core := extractFuncBody(t, source, "func (d *Service) terminalConnDo(")
	for _, want := range []string{"context.Background()", "d.recoveryDSN(", "retryBackoff(", "isConnError("} {
		if !strings.Contains(core, want) {
			t.Errorf("terminalConnDo must use %q (teardown-immune: own context.Background, fresh daemon-tagged conn, bounded retry); not found", want)
		}
	}
	// STATBUS-154 wave-6: the fresh session must self-exempt from the post-swap
	// read-only window (SET default_transaction_read_only = off), or the terminal
	// write/flip hits 25006 (a non-conn error → no retry → never lands).
	if !strings.Contains(core, "default_transaction_read_only = off") {
		t.Error("terminalConnDo must SET default_transaction_read_only = off on its fresh session — machinery writes through the read-only accident-guard (STATBUS-110/-021); without it the write hits 25006 and never lands")
	}
	// PIN ii: the core (and thus every wrapper) must NOT use the pass's shared
	// connection — a terminal write/flip uses a FRESH connection so it survives the
	// pass teardown.
	if strings.Contains(core, "d.queryConn") {
		t.Error("terminalConnDo must NOT use d.queryConn — a terminal write/flip uses a FRESH connection (STATBUS-154 PIN ii)")
	}
	// Both wrappers must DELEGATE to the shared core (no hand-rolled retry copy)
	// and neither may reach for the pass conn.
	for _, wrap := range []string{"func (d *Service) terminalUpdate(", "func (d *Service) terminalExec("} {
		w := extractFuncBody(t, source, wrap)
		if !strings.Contains(w, "d.terminalConnDo(") {
			t.Errorf("%s must delegate to the shared terminalConnDo (STATBUS-163 closing extraction) — no duplicated retry loop", wrap)
		}
		if strings.Contains(w, "d.queryConn") {
			t.Errorf("%s must NOT use d.queryConn — it rides the fresh-conn core", wrap)
		}
	}

	helper := extractFuncBody(t, source, "func (d *Service) writeRollbackTerminal(")
	if !strings.Contains(helper, "d.terminalUpdate(") {
		t.Error("writeRollbackTerminal must delegate to the shared terminalUpdate (STATBUS-154)")
	}
	if !strings.Contains(helper, "d.markTerminal(") {
		t.Error("writeRollbackTerminal must still fail loud via markTerminal on exhaustion")
	}
	// It must NOT remove the flag — the caller owns the conditional removal so the
	// flag is KEPT on failure. (Comments are stripped by extractFuncBody.)
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

// TestParkUpgrade_TeardownImmuneStructural pins STATBUS-154 at the site the arc
// caught: parkUpgrade (the park terminal) must write via the teardown-immune
// terminalUpdate, never d.queryConn (the pass's conn that teardown cancels), and
// must verify already-parked on a 0-row guard match so the exit invariant holds.
func TestParkUpgrade_TeardownImmuneStructural(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) parkUpgrade(")
	if !strings.Contains(body, "d.terminalUpdate(") {
		t.Error("parkUpgrade must write via the teardown-immune terminalUpdate (STATBUS-154)")
	}
	if strings.Contains(body, "d.queryConn") {
		t.Error("parkUpgrade must NOT use d.queryConn — the park write must survive the pass teardown (the health-park re-park red)")
	}
	if !strings.Contains(body, "rowIsParked") {
		t.Error("parkUpgrade must verify already-parked (rowIsParked) when the guarded UPDATE matches 0 rows — exit invariant AC#2")
	}
}

// TestTerminalWrite_SurvivesCanceledPassContext pins STATBUS-154 (i): a terminal
// write must not die with the pass. parkUpgrade is called with an ALREADY-CANCELED
// pass ctx; because it routes through terminalUpdate (context.Background, fresh
// conn) it still runs its own path and returns a connectivity error — NEVER
// context.Canceled. Had it used the pass ctx it would short-circuit with
// context.Canceled. DB-free: no .env in the TempDir → recoveryDSN/connect fails.
func TestTerminalWrite_SurvivesCanceledPassContext(t *testing.T) {
	projDir := t.TempDir() // no .env → terminalUpdate cannot reach a DB
	d := &Service{projDir: projDir}

	canceled, cancel := context.WithCancel(context.Background())
	cancel() // the pass is already torn down

	freshlyParked, err := d.parkUpgrade(canceled, 7, "test reason")
	if freshlyParked {
		t.Error("no DB → the park cannot land; freshlyParked must be false")
	}
	if err == nil {
		t.Fatal("expected an error when the DB is unreachable")
	}
	if errors.Is(err, context.Canceled) {
		t.Errorf("parkUpgrade used the canceled PASS ctx (got context.Canceled) — it must run under context.Background (STATBUS-154 PIN i); err=%v", err)
	}
}
