package upgrade

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

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

// TestRunStartupOrder_B1AndBootMigrateActivePhase is the structural guard for
// plan piece #2 (B1) + boot-migrate-move. The exit-42 RESUME
// (recoverFromFlag → resumeNewSb → applyNewSbUpgrading) and boot-migrate-up both
// run heavy, DB-size-scaled work; they MUST run in systemd's ACTIVE phase
// (post-READY=1, governed by WatchdogSec) rather than the START phase (under
// the fixed TimeoutStartSec that can't bound DB-size-scaled work — the NO/rune
// 40 h wedge). So in Service.Run, the required order is:
//
//	EnsureDBUp → connect → advisory lock
//	  → sdNotify("READY=1") + LISTEN          (B1 / Option Y)
//	  → boot-migrate-up                        (boot-migrate-move: active-phase)
//	  → recoverFromFlag → post-recovery → main loop
//
// This guard pins four orderings:
//  1. READY=1 BEFORE recoverFromFlag                (B1)
//  2. both LISTEN calls BEFORE recoverFromFlag      (B1, Option Y — a NOTIFY
//     arriving during recovery buffers on the session rather than being lost)
//  3. boot-migrate-up AFTER READY=1                 (boot-migrate runs active-phase)
//  4. boot-migrate-up BEFORE recoverFromFlag        (schema-skew guard: the
//     binary's column expectations must match the schema before recoverFromFlag's
//     first public.upgrade query)
//
// NOTE: #2 alone gives "resume runs active-phase under WatchdogSec". The
// progress-gated watchdog that makes a *hung* active-phase step get caught is
// plan piece #3 (separate commit) — this guard does not assert progress-gating.
func TestRunStartupOrder_B1AndBootMigrateActivePhase(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")

	readyIdx := strings.Index(run, `sdNotify("READY=1")`)
	recoverIdx := strings.Index(run, "d.recoverFromFlag(ctx)")
	listenCheckIdx := strings.Index(run, `"LISTEN upgrade_check"`)
	listenApplyIdx := strings.Index(run, `"LISTEN upgrade_apply"`)
	bootMigrateIdx := strings.Index(run, `"boot-migrate-up"`)

	for name, idx := range map[string]int{
		`sdNotify("READY=1")`:    readyIdx,
		"d.recoverFromFlag(ctx)": recoverIdx,
		`"LISTEN upgrade_check"`: listenCheckIdx,
		`"LISTEN upgrade_apply"`: listenApplyIdx,
		`"boot-migrate-up"`:      bootMigrateIdx,
	} {
		if idx < 0 {
			t.Fatalf("Service.Run missing %s — test is stale", name)
		}
	}

	if readyIdx > recoverIdx {
		t.Errorf(`sdNotify("READY=1") must be BEFORE d.recoverFromFlag(ctx) (B1): readyIdx=%d recoverIdx=%d.`+
			" The exit-42 resume must run active-phase under WatchdogSec, not start-phase under TimeoutStartSec "+
			"(the NO/rune wedge). See plan upgrade-resume-structural-whole.md piece #2.", readyIdx, recoverIdx)
	}
	if listenCheckIdx > recoverIdx || listenApplyIdx > recoverIdx {
		t.Errorf("both LISTEN calls must be BEFORE d.recoverFromFlag(ctx) (B1 Option Y): "+
			"check=%d apply=%d recover=%d. Registering LISTEN before recovery means a NOTIFY arriving "+
			"mid-recovery buffers on the session (drained by the main loop) rather than being lost.",
			listenCheckIdx, listenApplyIdx, recoverIdx)
	}
	if bootMigrateIdx < readyIdx {
		t.Errorf(`boot-migrate-up must be AFTER sdNotify("READY=1") (boot-migrate-move): bootMigrateIdx=%d readyIdx=%d.`+
			" A slow large-DB boot migration must run active-phase under WatchdogSec, not under the fixed "+
			"start-phase TimeoutStartSec. See plan piece #2 boot-migrate fold-in.", bootMigrateIdx, readyIdx)
	}
	if bootMigrateIdx > recoverIdx {
		t.Errorf("boot-migrate-up must be BEFORE d.recoverFromFlag(ctx) (schema-skew guard): bootMigrate=%d recover=%d. "+
			"recoverFromFlag's first public.upgrade query needs the schema migrated to HEAD, or it fails SQLSTATE 42703.",
			bootMigrateIdx, recoverIdx)
	}
}

// TestBootMigrateWatchdogCover_SourceOrder is the structural guard for the
// STATBUS-012 fix (design: backlog doc-005). boot-migrate-up runs in the
// ACTIVE phase (watchdog armed at READY=1) with the main-loop idle heartbeat
// ticker not yet created and the main goroutine parked in the subprocess
// wait — so it MUST carry its own always-ping WATCHDOG=1 ticker for the
// subprocess duration, bounded by the shared MigrateUpTimeout. Because
// executeUpgrade Step 6b unconditionally hands off post-swap, boot-migrate is
// the site that consumes EVERY upgrade's migration delta; without this cover
// a single >120 s migration SIGABRT-loops the unit indefinitely (the rune
// wedge, WatchdogSec edition). Empirical reproduction: install-recovery
// scenario 3-postswap-migration-timeout (service-dispatch rewrite).
//
// Pins five facts inside Service.Run:
//  1. the boot-migrate ticker arms AFTER sdNotify("READY=1") (it covers the
//     active-phase window — arming earlier would be meaningless, the watchdog
//     isn't counting yet)
//  2. the ticker arms BEFORE the boot-migrate subprocess runs
//  3. the ticker is cancelled AND joined (<-bootMigrateTickerDone) before
//     recoverFromFlag — an EXPLICIT bounded cover, not a process-lifetime
//     pinger that would mask later genuine main-goroutine hangs
//  4. the boot-migrate call is bounded by the shared MigrateUpTimeout (not a
//     site-local literal that can drift from the applyNewSbUpgrading migrate site)
//  5. the ticker passes nil progress (= ping unconditionally,
//     progress.go shouldPingWatchdog nil-receiver contract) — output-gating
//     would starve on a silent single-DDL migration, the exact case the
//     cover exists for
func TestBootMigrateWatchdogCover_SourceOrder(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")

	readyIdx := strings.Index(run, `sdNotify("READY=1")`)
	tickerArmIdx := strings.Index(run, "go runGatedWatchdogTicker(bootMigrateTickerCtx, nil,")
	bootMigrateIdx := strings.Index(run, `"boot-migrate-up"`)
	timeoutIdx := strings.Index(run, "MigrateUpTimeout, io.Discard")
	joinIdx := strings.Index(run, "<-bootMigrateTickerDone")
	recoverIdx := strings.Index(run, "d.recoverFromFlag(ctx)")

	for name, idx := range map[string]int{
		`sdNotify("READY=1")`:                       readyIdx,
		"bootMigrate ticker arm (nil progress)":     tickerArmIdx,
		`"boot-migrate-up"`:                         bootMigrateIdx,
		"MigrateUpTimeout at the boot-migrate call": timeoutIdx,
		"<-bootMigrateTickerDone join":              joinIdx,
		"d.recoverFromFlag(ctx)":                    recoverIdx,
	} {
		if idx < 0 {
			t.Fatalf("Service.Run missing %s — test is stale (STATBUS-012 cover removed or renamed?)", name)
		}
	}

	if tickerArmIdx < readyIdx {
		t.Errorf("boot-migrate watchdog ticker must arm AFTER sdNotify(\"READY=1\") "+
			"(tickerArm=%d ready=%d): the watchdog only counts in the active phase.", tickerArmIdx, readyIdx)
	}
	if bootMigrateIdx < tickerArmIdx {
		t.Errorf("boot-migrate-up must run AFTER its ticker arms (bootMigrate=%d tickerArm=%d): "+
			"the subprocess wait parks the main goroutine with zero other WATCHDOG=1 sources (STATBUS-012).",
			bootMigrateIdx, tickerArmIdx)
	}
	if joinIdx < bootMigrateIdx {
		t.Errorf("the ticker cancel+join must come AFTER the boot-migrate call (join=%d bootMigrate=%d).",
			joinIdx, bootMigrateIdx)
	}
	if joinIdx > recoverIdx {
		t.Errorf("the ticker must be joined BEFORE d.recoverFromFlag (join=%d recover=%d): "+
			"the cover is an EXPLICIT BOUNDED defer — left running it would mask a genuine "+
			"main-goroutine hang for the rest of the process lifetime.", joinIdx, recoverIdx)
	}
}
