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
	rb := extractFuncBody(t, string(src), "func (d *Service) rollback(")

	tickerArmIdx := strings.Index(rb, "go runGatedWatchdogTicker(rollbackTickerCtx, nil,")
	cancelIdx := strings.Index(rb, "rollbackTickerCancel()")
	joinIdx := strings.Index(rb, "<-rollbackTickerDone")
	restoreIdx := strings.Index(rb, "d.restoreDatabase(")
	dockerUpIdx := strings.Index(rb, `"rollback-docker-up"`)

	for name, idx := range map[string]int{
		"rollback always-ping watchdog ticker arm (nil progress)": tickerArmIdx,
		"rollbackTickerCancel()":                                  cancelIdx,
		"<-rollbackTickerDone join":                               joinIdx,
		"d.restoreDatabase( call":                                 restoreIdx,
		`"rollback-docker-up" call`:                               dockerUpIdx,
	} {
		if idx < 0 {
			t.Fatalf("Service.rollback missing %s — STATBUS-031 watchdog cover removed or renamed?", name)
		}
	}

	if restoreIdx < tickerArmIdx {
		t.Errorf("the always-ping watchdog ticker must arm BEFORE restoreDatabase "+
			"(tickerArm=%d restore=%d): the whole-volume rsync is heartbeat-silent and on the "+
			"startup recovery path otherwise uncovered → WatchdogSec kills it mid-restore (STATBUS-031).",
			tickerArmIdx, restoreIdx)
	}
	if dockerUpIdx < tickerArmIdx {
		t.Errorf("the always-ping watchdog ticker must arm BEFORE the rollback docker-up "+
			"(tickerArm=%d dockerUp=%d): it is also onAdvance=nil silent.", tickerArmIdx, dockerUpIdx)
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
