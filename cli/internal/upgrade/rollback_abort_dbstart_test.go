package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestRollbackAbort_StartsDBBeforeTerminalWrite is the structural guard for
// STATBUS-136. rollback()'s git-restore ABORT branch stops every service
// (including db) for the restore and — unlike the normal rollback path, which
// runs `docker compose up -d` before its terminal write — never brings them
// back up. Before this fix the abort branch's `state='failed'` terminal write
// therefore targeted a STOPPED database: writeRollbackTerminal's bounded
// reconnect had nothing to connect to, exhausted, tripped INVARIANT
// ROLLBACK_TERMINAL_WRITE_FAILED, KEPT the flag, and the process exited →
// systemd re-ran the whole abort → a guaranteed death loop on a path that had
// already concluded (observed live in r17, ×3).
//
// The fix starts the EXISTING db container (StartDBForRecovery = the
// asymmetric-safe `docker compose start db`, never `up -d`) BEFORE the terminal
// write, so the write can land and the box ends in a named `failed` state
// instead of restarting forever.
//
// rollback() runs real docker + os.Exit, so it is not unit-runnable in-process;
// this pins the load-bearing ORDERING structurally on the source, matching the
// source-body assertion pattern used across postswap_test.go. The live proof is
// the STATBUS-134 rollback-crash-loop scenario (a later unit).
func TestRollbackAbort_StartsDBBeforeTerminalWrite(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	// extractFuncBody strips line comments, so the prose in the fix's own
	// comment (which names these very tokens) cannot create a false match.
	body := extractFuncBody(t, string(src), "func (d *Service) rollback(")

	startIdx := strings.Index(body, "d.StartDBForRecovery(ctx)")
	if startIdx < 0 {
		t.Fatal("rollback() abort branch must call d.StartDBForRecovery(ctx) to bring the stopped db back up before recording the failed terminal (STATBUS-136); not found")
	}

	// LabelFailedAbort is unique to the abort branch's terminal write; the
	// normal rollback path uses other labels. Pin start-db BEFORE that write.
	abortWriteIdx := strings.Index(body, "LabelFailedAbort")
	if abortWriteIdx < 0 {
		t.Fatal("rollback() abort branch's terminal write (LabelFailedAbort) not found — test is stale")
	}

	if startIdx >= abortWriteIdx {
		t.Fatalf("STATBUS-136 ordering violated: StartDBForRecovery (idx %d) must precede the abort terminal write LabelFailedAbort (idx %d) — otherwise the write hits a stopped DB and loops", startIdx, abortWriteIdx)
	}
}
