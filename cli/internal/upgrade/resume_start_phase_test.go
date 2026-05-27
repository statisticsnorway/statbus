package upgrade

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// Structural guards for the recovery-arc start-phase fix
// (plan: recovery-arc-flaw-timeoutstartsec.md §4a). These pin the two
// source-level orderings that keep an exit-42 RESUME from wedging a unit
// in systemd's `activating` (start) phase under TimeoutStartSec.
//
// Why source-order guards rather than a behavioral test: the failure only
// manifests against a live systemd unit + a large DB (the full reproduction
// lives in the install-recovery harness, scenario 27, which runs on the
// Hetzner CI box at RC-cut). These guards run locally in `go test` and
// fail loudly the instant a future edit re-introduces the ordering bug —
// the same discipline as TestRecoverFromFlag_PhaseDiscriminationPresent
// and TestResumePostSwap_SelfHealContinueOrFailLoud in postswap_test.go.

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

// TestReadyEmittedBeforeRecoverFromFlag is the structural guard for FIX B1.
//
// recoverFromFlag → resumePostSwap → applyPostSwap is the exit-42 resume
// path. It runs inside Service.Run's startup, and BEFORE the fix it ran
// entirely before sdNotify("READY=1") — i.e. in systemd's `activating`
// phase under TimeoutStartSec=120 s. A large-DB resume step (archiveBackup
// tars a 32 GB DB on NO/rune) cannot finish in that budget, so systemd
// SIGTERMs the unit mid-step, the terminal UPDATE never persists, the row
// stays in_progress, and Restart=always re-enters the identical doomed
// resume — an infinite loop (NO wedged ~40 h, NRestarts 914).
//
// The fix emits READY=1 after the cheap genuine init (EnsureDBUp /
// boot-migrate-up / connect / advisory lock) but BEFORE recoverFromFlag,
// so the whole resume runs in the ACTIVE phase under WatchdogSec — where
// the existing 30 s WATCHDOG=1 ticker (applyPostSwap) actually keeps the
// unit alive. This guard pins READY=1 < recoverFromFlag in Service.Run.
func TestReadyEmittedBeforeRecoverFromFlag(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")

	readyIdx := strings.Index(run, `sdNotify("READY=1")`)
	if readyIdx < 0 {
		t.Fatal(`Service.Run missing sdNotify("READY=1") — test is stale`)
	}
	recoverIdx := strings.Index(run, "d.recoverFromFlag(ctx)")
	if recoverIdx < 0 {
		t.Fatal("Service.Run missing d.recoverFromFlag(ctx) call — test is stale")
	}

	if readyIdx > recoverIdx {
		t.Errorf(`sdNotify("READY=1") must be emitted BEFORE d.recoverFromFlag(ctx) `+
			"(readyIdx=%d, recoverIdx=%d).\n"+
			"On the exit-42 resume path recoverFromFlag → resumePostSwap → applyPostSwap "+
			"runs the whole heavy pipeline (incl. archiveBackup). If READY=1 has not yet "+
			"fired, that pipeline runs in systemd's `activating` phase under TimeoutStartSec; "+
			"a large-DB step blows the budget, the unit is SIGTERM'd before the terminal "+
			"UPDATE persists, and the service restart-loops forever (the NO/rune wedge). "+
			"Emit READY=1 after the cheap init (EnsureDBUp/boot-migrate/connect/advisory-lock) "+
			"but before recoverFromFlag so the resume runs ACTIVE-phase under WatchdogSec. "+
			"See plan recovery-arc-flaw-timeoutstartsec.md §4a FIX B1.", readyIdx, recoverIdx)
	}
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
