package upgrade

import (
	"os"
	"strings"
	"testing"
	"time"
)

// TestReadOnlyWindowFlip_TeardownImmune_STATBUS163 pins the 163 shape: the terminal
// read-only-window OFF flips ride the teardown-immune terminalExec (never the
// dying pass conn), a failed flip escalates loudly (never complete-with-warning),
// the ON site stays best-effort on the live conn, and the boot backstop exists.
func TestReadOnlyWindowFlip_TeardownImmune_STATBUS163(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	source := string(src)

	// (1) terminalExec is teardown-immune, mirroring terminalUpdate: own
	//     context.Background, fresh daemon-tagged conn via recoveryDSN, bounded
	//     retry, self-exempt SET off; and NEVER the pass's d.queryConn.
	ex := extractFuncBody(t, source, "func (d *Service) terminalExec(")
	for _, want := range []string{"context.Background()", "d.recoveryDSN(", "retryBackoff(", "isConnError(", "default_transaction_read_only = off"} {
		if !strings.Contains(ex, want) {
			t.Errorf("terminalExec must use %q (teardown-immune like terminalUpdate); not found", want)
		}
	}
	if strings.Contains(ex, "d.queryConn") {
		t.Error("terminalExec must NOT use d.queryConn — the terminal window flip needs a FRESH connection (STATBUS-163/154 PIN ii)")
	}

	// (2) BOTH terminal OFF flips ride terminalExec(windowOffSQL); the
	//     complete-with-warning lines are GONE; a failed flip escalates via a named
	//     invariant (markTerminal-class), not a Warning.
	if n := strings.Count(source, "d.terminalExec(windowOffSQL)"); n < 2 {
		t.Errorf("both terminal OFF sites (completion + rollback) must flip via terminalExec(windowOffSQL); found %d", n)
	}
	for _, gone := range []string{
		"Warning: could not clear read-only window at completion",
		"Warning: could not clear read-only window after rollback",
	} {
		if strings.Contains(source, gone) {
			t.Errorf("the complete-with-warning line %q must be GONE — a failed OFF flip escalates loudly (STATBUS-163 invariant)", gone)
		}
	}
	for _, inv := range []string{"COMPLETION_READ_ONLY_WINDOW_LIFTED", "ROLLBACK_READ_ONLY_WINDOW_LIFTED"} {
		if !strings.Contains(source, inv) {
			t.Errorf("a failed OFF flip must escalate via the named invariant %q (markTerminal-class), never a Warning", inv)
		}
	}

	// (3) The ON site stays best-effort on the LIVE pass conn (setDatabaseReadOnly,
	//     NOT terminalExec) — the ratified asymmetry: failing to ENGAGE degrades
	//     protection; failing to LIFT wedges the box.
	if !strings.Contains(source, "d.setDatabaseReadOnly(ctx, true)") {
		t.Error("the ON site must stay setDatabaseReadOnly(ctx, true) on the live pass conn (STATBUS-163 asymmetry)")
	}

	// (4) The boot backstop rides terminalExec, gated on no-flag + no-in_progress +
	//     the DATABASE-level read-only default, and is wired into boot.
	bs := extractFuncBody(t, source, "func (d *Service) clearStaleReadOnlyWindow(")
	for _, want := range []string{"ReadFlagFile(", "state = 'in_progress'", "pg_db_role_setting", "d.terminalExec(windowOffSQL)"} {
		if !strings.Contains(bs, want) {
			t.Errorf("clearStaleReadOnlyWindow must contain %q (no-flag + no-in_progress + DB-level-RO gate, immune clear); not found", want)
		}
	}
	if !strings.Contains(source, "d.clearStaleReadOnlyWindow(ctx)") {
		t.Error("clearStaleReadOnlyWindow must be wired into boot (next to cleanStaleMaintenance)")
	}
}

// TestTerminalExec_TeardownImmuneBehavioral_STATBUS163 proves terminalExec does not
// ride the pass's connection: called on a Service whose queryConn is nil (the pass
// conn "closed"), with no .env so recoveryDSN fails each attempt, it must NOT panic
// (never touches d.queryConn) and must run its OWN bounded retry (its own
// context.Background) before returning an error — not abort instantly.
func TestTerminalExec_TeardownImmuneBehavioral_STATBUS163(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir} // queryConn is nil — the "closed pass conn"

	start := time.Now()
	err := d.terminalExec(windowOffSQL) // no ctx arg by design — own Background
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("terminalExec must return an error when recoveryDSN cannot resolve (no .env) — it did not")
	}
	// It ran its bounded retry on its own Background loop (recoveryDSN fails fast,
	// then backoff between attempts) rather than aborting instantly — and did NOT
	// nil-panic on the absent d.queryConn, proving it uses a FRESH connection.
	if elapsed < 500*time.Millisecond {
		t.Errorf("terminalExec returned too fast (%v) — it must run its bounded retry on its OWN context.Background, independent of the pass conn", elapsed)
	}
}
