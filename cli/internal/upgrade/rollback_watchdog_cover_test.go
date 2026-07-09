package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestRollbackWatchdogCover_SourceOrder is the structural guard for STATBUS-031:
// rollback()'s body runs the two heartbeat-SILENT, DB-size-scaled steps an upgrade
// has — restoreDatabase's whole-volume rsync (onAdvance=nil) and the rollback
// docker-up (onAdvance=nil). On the STARTUP recovery path (recoverFromFlag →
// recoveryRollback → rollback) NO other watchdog ticker is armed, so without an
// always-ping cover a >120s restore (Norway 32 GB ⇒ guaranteed) trips WatchdogSec
// mid-restore → flag still present → next boot restores from scratch → killed again
// = indefinite restore loop. This pins, at the source level (the systemctl/docker
// calls shell out, so a behavioral test needs a real VM — that's the RED→GREEN
// harness pair), that the cover is present and ordered correctly:
//  1. an ALWAYS-PING ticker (nil progress) arms at the TOP of rollback()
//  2. it arms BEFORE the first restoreDatabase call (the silent rsync it covers)
//  3. it arms BEFORE the rollback-docker-up (also silent)
//  4. the ticker is cancelled AND joined (deferred — rollback() returns only via
//     os.Exit today, so the defer is insurance for any future early-return path)
//  5. restoreDatabase's rsync is bounded by the shared RestoreDBTimeout, not a
//     site-local literal that can drift from the generous-budget doctrine
func TestRollbackWatchdogCover_SourceOrder(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	source := string(src)
	rb := extractFuncBody(t, source, "func (d *Service) rollback(")
	// STATBUS-111: the two heartbeat-silent steps (restoreDatabase rsync +
	// rollback-docker-up) were extracted from rollback() into restoreAndFinalize
	// (PIN 1). The always-ping cover invariant is UNCHANGED — it now reads:
	// every caller of restoreAndFinalize arms the ticker BEFORE the call, and the
	// silent steps live inside restoreAndFinalize.
	raf := extractFuncBody(t, source, "func (d *Service) restoreAndFinalize(")
	rar := extractFuncBody(t, source, "func (d *Service) ReattemptRestore(")

	// (1) rollback() arms the always-ping ticker at the top and calls the
	// extracted tail UNDER that cover.
	tickerArmIdx := strings.Index(rb, "go runGatedWatchdogTicker(rollbackTickerCtx, nil,")
	cancelIdx := strings.Index(rb, "rollbackTickerCancel()")
	joinIdx := strings.Index(rb, "<-rollbackTickerDone")
	rbCallIdx := strings.Index(rb, "d.restoreAndFinalize(")
	for name, idx := range map[string]int{
		"rollback always-ping watchdog ticker arm (nil progress)": tickerArmIdx,
		"rollbackTickerCancel()":                                  cancelIdx,
		"<-rollbackTickerDone join":                               joinIdx,
		"rollback → restoreAndFinalize call":                      rbCallIdx,
	} {
		if idx < 0 {
			t.Fatalf("Service.rollback missing %s — STATBUS-031/-111 watchdog cover removed or renamed?", name)
		}
	}
	if rbCallIdx < tickerArmIdx {
		t.Errorf("rollback() must arm the always-ping watchdog BEFORE calling restoreAndFinalize "+
			"(tickerArm=%d call=%d): the extracted rsync + docker-up are heartbeat-silent (STATBUS-031).",
			tickerArmIdx, rbCallIdx)
	}

	// (2) The extracted tail holds the two silent steps.
	if !strings.Contains(raf, "d.restoreDatabase(") {
		t.Error("restoreAndFinalize must contain the restoreDatabase rsync (the silent step it was extracted with)")
	}
	if !strings.Contains(raf, `"rollback-docker-up"`) {
		t.Error("restoreAndFinalize must contain the rollback-docker-up (also onAdvance=nil silent)")
	}
	// It must NOT arm its own ticker — PIN 1: the cover is caller-owned (one
	// cover per call site; a nested self-cover would double-ping).
	if strings.Contains(raf, "runGatedWatchdogTicker(") {
		t.Error("restoreAndFinalize must NOT arm a watchdog itself — PIN 1: callers own the cover")
	}

	// (3) STATBUS-111: the install-driven re-attempt runs the SAME tail, so it
	// MUST arm its own cover BEFORE calling restoreAndFinalize.
	rarTickerIdx := strings.Index(rar, "go runGatedWatchdogTicker(")
	rarCallIdx := strings.Index(rar, "d.restoreAndFinalize(")
	if rarTickerIdx < 0 || rarCallIdx < 0 {
		t.Fatalf("ReattemptRestore must arm a watchdog ticker AND call restoreAndFinalize (ticker=%d call=%d)", rarTickerIdx, rarCallIdx)
	}
	if rarCallIdx < rarTickerIdx {
		t.Errorf("ReattemptRestore must arm the watchdog BEFORE calling restoreAndFinalize (ticker=%d call=%d)", rarTickerIdx, rarCallIdx)
	}

	// (4) STATBUS-111 (architect review): the re-attempt probe also matches the
	// git-restore ABORT row (tree corrupt). ReattemptRestore MUST restore git
	// state FIRST — before the destructive stop + restoreAndFinalize — or an
	// abort-row re-attempt restores binary+DB onto a wreckage tree → mixed-era.
	rarGitIdx := strings.Index(rar, "d.restoreGitState(")
	rarStopIdx := strings.Index(rar, `"stop", "app", "worker", "rest", "db"`)
	if rarGitIdx < 0 {
		t.Fatal("ReattemptRestore must call restoreGitState (the abort-row mixed-era guard) before the DB re-attempt")
	}
	if rarGitIdx > rarCallIdx {
		t.Errorf("ReattemptRestore must restore git state BEFORE restoreAndFinalize (git=%d restoreAndFinalize=%d) — else an abort-row re-attempt comes up mixed-era", rarGitIdx, rarCallIdx)
	}
	if rarStopIdx >= 0 && rarGitIdx > rarStopIdx {
		t.Errorf("ReattemptRestore must restore git state BEFORE the destructive db stop (git=%d stop=%d)", rarGitIdx, rarStopIdx)
	}

	// The restore rsync must use the shared RestoreDBTimeout, not a site-local
	// literal that can drift from MigrateUpTimeout's generous-budget doctrine.
	execSrc, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/exec.go"))
	if err != nil {
		t.Fatalf("read exec.go: %v", err)
	}
	restoreBody := extractFuncBody(t, string(execSrc), "func (d *Service) restoreDatabase(")
	if !strings.Contains(restoreBody, "RestoreDBTimeout") {
		t.Error("restoreDatabase must bound its rsync with the shared RestoreDBTimeout (STATBUS-031), " +
			"not a site-local 10*time.Minute literal.")
	}
	if strings.Contains(restoreBody, "10 * time.Minute") || strings.Contains(restoreBody, "10*time.Minute") {
		t.Error("restoreDatabase still carries a 10-minute literal timeout — replace with the shared RestoreDBTimeout (STATBUS-031).")
	}
}
