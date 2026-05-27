package upgrade

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// Structural guard for the recovery-arc start-phase fix
// (plan: recovery-arc-flaw-timeoutstartsec.md §4a, FIX A). Pins the
// source-level ordering that keeps an exit-42 RESUME from wedging a unit:
// the terminal state='completed' UPDATE + flag removal must run BEFORE the
// slow, kill-prone archiveBackup. On the resume path archiveBackup runs in
// systemd's `activating` (start) phase under TimeoutStartSec; reordering it
// after the terminal UPDATE means a SIGTERM mid-tar leaves a COMPLETED
// upgrade the next start no-ops past, instead of cancelling the DB context
// before the UPDATE persists (the NO/rune wedge mechanism).
//
// Why a source-order guard rather than a behavioral test: the failure only
// manifests against a live systemd unit + a large DB (the full reproduction
// lives in the install-recovery harness, scenario 27, which runs on the
// Hetzner CI box at RC-cut). This guard runs locally in `go test` and fails
// loudly the instant a future edit re-introduces the ordering bug — the same
// discipline as TestRecoverFromFlag_PhaseDiscriminationPresent and
// TestResumePostSwap_SelfHealContinueOrFailLoud in postswap_test.go.

// extractFuncBody returns the source of the named top-level method body
// (signature line through the matching column-0 closing brace), with line
// comments stripped so historical-note prose mentioning the very tokens
// these guards search for cannot create false matches. Matches the
// extraction shape used across postswap_test.go.
func extractFuncBody(t *testing.T, src, signature string) string {
	t.Helper()
	start := strings.Index(src, signature)
	if start < 0 {
		t.Fatalf("%q not found in service.go — test is stale", signature)
	}
	rest := src[start:]
	end := regexp.MustCompile(`(?m)^}\n`).FindStringIndex(rest)
	if end == nil {
		t.Fatalf("closing brace for %q not found", signature)
	}
	return stripLineComments(rest[:end[1]])
}

// TestArchiveBackupAfterTerminalUpdate is the structural guard for FIX A.
//
// On NO the SIGTERM that killed the start-phase archiveBackup also cancelled
// the DB context, so the terminal `state='completed'` UPDATE that runs AFTER
// archiveBackup could not persist ("context already done: context canceled")
// and the reconnect-retry failed too (RECONNECT_ON_STALE_CONN_SUCCEEDS) —
// the row never reached completed → loop. archiveBackup is non-critical-path
// (it tars the pre-upgrade backup for forensics; pruneBackups already runs
// post-completion). Reordering it AFTER the terminal UPDATE + removeUpgradeFlag
// means the fast UPDATE persists inside even a 90 s start budget, the flag is
// gone, and a subsequent kill during the tar is harmless: the next start
// finds no flag and no-ops. This converges NO regardless of which systemd
// timer fires, and is the single highest-leverage change.
//
// Guard: within applyPostSwap, the d.archiveBackup(...) call must come AFTER
// both the state='completed' terminal UPDATE and d.removeUpgradeFlag().
func TestArchiveBackupAfterTerminalUpdate(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) applyPostSwap(")

	archiveIdx := strings.Index(body, "d.archiveBackup(")
	if archiveIdx < 0 {
		t.Fatal("applyPostSwap missing d.archiveBackup( call — test is stale")
	}
	// The terminal UPDATE is issued via the completedSQL string built in
	// applyPostSwap; match the SET clause that marks the row completed.
	completedIdx := strings.Index(body, "SET state = 'completed'")
	if completedIdx < 0 {
		t.Fatal("applyPostSwap missing the state='completed' terminal UPDATE — test is stale")
	}
	removeFlagIdx := strings.Index(body, "d.removeUpgradeFlag()")
	if removeFlagIdx < 0 {
		t.Fatal("applyPostSwap missing d.removeUpgradeFlag() — test is stale")
	}

	if archiveIdx < completedIdx {
		t.Errorf("d.archiveBackup(...) must run AFTER the state='completed' terminal UPDATE "+
			"(archiveIdx=%d, completedIdx=%d).\n"+
			"A SIGTERM during the multi-minute archiveBackup tar cancels the DB context; "+
			"if the terminal UPDATE runs after the tar it cannot persist (context canceled) "+
			"and the row stays in_progress → restart loop (the NO/rune wedge). Move "+
			"archiveBackup to AFTER the terminal UPDATE so the fast UPDATE persists inside "+
			"the systemd budget. See plan recovery-arc-flaw-timeoutstartsec.md §4a FIX A.",
			archiveIdx, completedIdx)
	}
	if archiveIdx < removeFlagIdx {
		t.Errorf("d.archiveBackup(...) must run AFTER d.removeUpgradeFlag() "+
			"(archiveIdx=%d, removeFlagIdx=%d).\n"+
			"The flag must be removed before the kill-prone tar so that a SIGTERM during "+
			"archiveBackup leaves NO flag on disk — the next service start then finds no "+
			"flag and no-ops instead of re-entering the doomed resume. "+
			"See plan recovery-arc-flaw-timeoutstartsec.md §4a FIX A.", archiveIdx, removeFlagIdx)
	}
}
