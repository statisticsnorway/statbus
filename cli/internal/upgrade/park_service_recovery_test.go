package upgrade

import (
	"strings"
	"testing"
)

// TestParkEraDecision_SourceIdentity is the STATBUS-200 era-guard oracle (RED-first): the
// verdict is a SOURCE-IDENTITY comparison, permit iff db_max == source_max. It fails on the
// withdrawn "permit iff !HasPending" design — which would PERMIT the post-delta case (the
// mixed-era corruption this guard exists to prevent) and REFUSE the pre-delta case.
func TestParkEraDecision_SourceIdentity(t *testing.T) {
	cases := []struct {
		name    string
		dbMax   int64
		srcMax  int64
		permit  bool
		wantSub string // required substring of the refusal narrative (only when !permit)
	}{
		{"codeonly-permit (no migrations either side)", 0, 0, true, ""},
		{"pre-delta-permit (DB at source; delta pending but UNAPPLIED)", 20260712000000, 20260712000000, true, ""},
		{"post-delta-refuse (delta APPLIED; DB past source — mixed-era)", 20260713000000, 20260712000000, false, "migration delta applied"},
		{"behind-refuse (DB below source — anomaly, fail safe)", 20260711000000, 20260712000000, false, "behind the source version"},
	}
	for _, c := range cases {
		permit, narrative := parkEraDecision(c.dbMax, c.srcMax)
		if permit != c.permit {
			t.Errorf("%s: permit=%v, want %v (db_max=%d src_max=%d)", c.name, permit, c.permit, c.dbMax, c.srcMax)
		}
		if c.permit {
			if narrative != "" {
				t.Errorf("%s: a permit must carry an EMPTY narrative, got %q", c.name, narrative)
			}
			continue
		}
		if !strings.Contains(narrative, c.wantSub) {
			t.Errorf("%s: refusal narrative %q must contain %q (the operator-visible reason)", c.name, narrative, c.wantSub)
		}
		if !strings.Contains(narrative, "services held down") {
			t.Errorf("%s: every refusal must name 'services held down' so the park narrative reads honestly, got %q", c.name, narrative)
		}
	}
}

// TestParkMigrationMaxInGitTree_ParsesVersions pins the source-max reader's filename parse:
// only *.up.sql/*.up.psql count, and the 14-digit prefix is the version. (Reads the LIVE repo
// tree at HEAD via a real git ls-tree — a non-negative max proves the parse path works.)
func TestParkMigrationMaxInGitTree_ParsesVersions(t *testing.T) {
	// HEAD is guaranteed resolvable in the repo; the migrations/ dir has many *.up.sql files.
	max, err := migrationMaxInGitTree(thisRepoFile(t, "."), "HEAD")
	if err != nil {
		t.Fatalf("migrationMaxInGitTree(HEAD): %v", err)
	}
	if max <= 0 {
		t.Fatalf("expected a positive migration max in the HEAD tree, got %d — the ls-tree parse found no *.up.sql versions", max)
	}
}

// TestParkServiceRecovery_StructuralContracts pins the STATBUS-200 build invariants by source
// inspection (no DB needed): the ordering pin, the helper-never-stops hard rule, serve-proven
// window ordering, restoreDatabase-skip, the appendParkNarrative single-caller pin, and its
// narrative-only (never a park write) shape.
func TestParkServiceRecovery_StructuralContracts(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])

	// ORDERING PIN (park write FIRST): parkServiceRecovery is invoked AFTER the parkUpgrade
	// call inside parkForDeterministicFailure — a crash mid-restoration leaves a parked row.
	pf := extractFuncBody(t, src, "func (d *Service) parkForDeterministicFailure(")
	parkIdx := strings.Index(pf, "d.parkUpgrade(")
	recIdx := strings.Index(pf, "d.parkServiceRecovery(")
	if parkIdx < 0 || recIdx < 0 || recIdx < parkIdx {
		t.Errorf("ordering pin: parkServiceRecovery must be called AFTER parkUpgrade in parkForDeterministicFailure (park write FIRST) — parkUpgrade@%d, parkServiceRecovery@%d", parkIdx, recIdx)
	}

	// HELPER NEVER STOPS ANYTHING (ruling Q4 hard rule): neither the helper nor the restore
	// tail may stop/down services or re-engage maintenance / read-only — they only ever START.
	for _, fn := range []string{"func (d *Service) parkServiceRecovery(", "func (d *Service) restoreSourceServices("} {
		body := extractFuncBody(t, src, fn)
		for _, forbidden := range []string{`"stop"`, `"down"`, "QuiesceClients", "setMaintenance(true)", "setDatabaseReadOnly(ctx, true)"} {
			if strings.Contains(body, forbidden) {
				t.Errorf("helper-never-stops: %s must not contain %q — the park-recovery helper may only START services, never stop anything", fn, forbidden)
			}
		}
	}

	// SERVE-PROVEN: in restoreSourceServices the read-only window lift comes AFTER the health
	// gate — maintenance/window drop only on a proven-serving box.
	rs := extractFuncBody(t, src, "func (d *Service) restoreSourceServices(")
	hcIdx := strings.Index(rs, "d.healthCheck(")
	// RETARGETED, NOT WEAKENED (STATBUS-266): the terminal OFF now flips through
	// d.liftReadOnlyWindow(), a one-line wrapper that runs the SAME
	// terminalExec(windowOffSQL) and additionally announces success. The property
	// below is unchanged; only the call's spelling moved.
	winIdx := strings.Index(rs, "liftReadOnlyWindow(")
	if hcIdx < 0 || winIdx < 0 || winIdx < hcIdx {
		t.Errorf("serve-proven: the read-only window lift must come AFTER the health gate in restoreSourceServices — healthCheck@%d, windowLift@%d", hcIdx, winIdx)
	}
	// restoreDatabase is DELIBERATELY skipped (ruling Q2 — the era guard makes it unnecessary).
	if strings.Contains(rs, "restoreDatabase(") {
		t.Error("restoreSourceServices must NOT call restoreDatabase — the era guard proves the DB is at source, so a DB restore is unnecessary and its absence is the mixed-era safeguard (ruling Q2)")
	}
	// LOCAL images only: the compose up must be --no-build (no pull; the disk is full).
	if !strings.Contains(rs, "--no-build") {
		t.Error("restoreSourceServices must start services with --no-build (LOCAL source images, no pull — the disk is full)")
	}

	// appendParkNarrative SINGLE-CALLER PIN: every call site is inside parkServiceRecovery.
	psr := extractFuncBody(t, src, "func (d *Service) parkServiceRecovery(")
	inHelper := strings.Count(psr, "d.appendParkNarrative(")
	inFile := strings.Count(src, "d.appendParkNarrative(")
	if inFile == 0 || inFile != inHelper {
		t.Errorf("appendParkNarrative single-caller pin: all call sites must be inside parkServiceRecovery — found %d in-file, %d in-helper", inFile, inHelper)
	}

	// appendParkNarrative is NARRATIVE-ONLY: it appends to reason/error, guards on an
	// already-parked row, and NEVER assigns recovery_parked_at (the STATBUS-196 single-park-
	// writer discipline — parkUpgrade stays the only park-timestamp writer).
	an := extractFuncBody(t, src, "func (d *Service) appendParkNarrative(")
	if strings.Contains(an, "recovery_parked_at =") {
		t.Error("appendParkNarrative must never ASSIGN recovery_parked_at — it is narrative-only (SingleParkWriter discipline, STATBUS-196)")
	}
	if !strings.Contains(an, "recovery_parked_at IS NOT NULL") {
		t.Error("appendParkNarrative must guard on `recovery_parked_at IS NOT NULL` — it may only extend an ALREADY-parked row's narrative")
	}
	if !strings.Contains(an, "recovery_parked_reason") || !strings.Contains(an, "error =") {
		t.Error("appendParkNarrative must append to BOTH recovery_parked_reason and error (the operator surfaces both)")
	}
}

// TestBudgetParks_RouteThroughHelper_STATBUS204 (AC#1/AC#3): the two budget-park sites route
// through parkServiceRecovery AFTER their park write, and NO park site anywhere bypasses the
// helper. RED before 204 (the budget sites called parkUpgrade directly and returned dark).
func TestBudgetParks_RouteThroughHelper_STATBUS204(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])

	// Both budget-park functions call parkServiceRecovery AFTER their parkUpgrade write (park
	// write first — the helper's hard rule).
	for _, fn := range []string{"func (d *Service) RecoveryBudgetGuard(", "func (d *Service) resumeNewSb("} {
		body := extractFuncBody(t, src, fn)
		parkIdx := strings.Index(body, "d.parkUpgrade(")
		recIdx := strings.Index(body, "d.parkServiceRecovery(")
		if parkIdx < 0 || recIdx < 0 || recIdx < parkIdx {
			t.Errorf("STATBUS-204: %s must call parkServiceRecovery AFTER its parkUpgrade write (park-first) — parkUpgrade@%d, parkServiceRecovery@%d", fn, parkIdx, recIdx)
		}
	}

	// AC#1 grep-pin (drift-proof, catches future sites too): EVERY function that writes a park
	// (calls d.parkUpgrade) must also route through parkServiceRecovery. A new bypassing park
	// site fails here until it goes through the chokepoint.
	for _, chunk := range strings.Split(src, "\nfunc ") {
		if !strings.Contains(chunk, "d.parkUpgrade(") {
			continue
		}
		if !strings.Contains(chunk, "d.parkServiceRecovery(") {
			name := chunk
			if nl := strings.IndexByte(chunk, '\n'); nl >= 0 {
				name = chunk[:nl]
			}
			t.Errorf("STATBUS-204 AC#1: a park site (func %s) writes a park via parkUpgrade but BYPASSES parkServiceRecovery — every park must route through the chokepoint so every parked box is operable", strings.TrimSpace(name))
		}
	}
}

// TestParkServiceRecovery_SelfCoveringWatchdog_STATBUS204 (cover pin, source-parsing family):
// parkServiceRecovery owns its watchdog cover — a gated ticker wraps its slow span and PRECEDES
// the parkEraVerdict call (so StartDBForRecovery's DB-health wait is inside the cover). A
// refactor that drops or mis-places the ticker fails here.
func TestParkServiceRecovery_SelfCoveringWatchdog_STATBUS204(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	psr := extractFuncBody(t, src, "func (d *Service) parkServiceRecovery(")

	tickIdx := strings.Index(psr, "runGatedWatchdogTicker(")
	if tickIdx < 0 {
		t.Fatal("STATBUS-204: parkServiceRecovery must own its watchdog cover — a runGatedWatchdogTicker must wrap its slow span (budget-park callers have no outer ticker)")
	}
	verdictIdx := strings.Index(psr, "d.parkEraVerdict(")
	if verdictIdx < 0 || tickIdx > verdictIdx {
		t.Errorf("STATBUS-204: the watchdog ticker must PRECEDE parkEraVerdict — StartDBForRecovery's ~60s DB-health wait is inside the danger window (ticker@%d must be before verdict@%d)", tickIdx, verdictIdx)
	}
	// The cover must be released (cancel + join) so it never outlives the helper.
	if !strings.Contains(psr, "tickerCancel()") || !strings.Contains(psr, "<-tickerDone") {
		t.Error("STATBUS-204: the watchdog ticker must be cancelled + joined (defer) so it cannot outlive the helper")
	}
}

// TestParkServiceRecovery_TruthRestoresFlag_STATBUS210, AMENDED BY STATBUS-229
// (architect-ruled, 2026-08-18).
//
// 210's SURVIVING invariants, all still pinned below: on the era-permitted SUCCESS arm — and ONLY
// there — parkServiceRecovery records the completed retreat on the held flag, keeping BackupPath;
// the refusal and failure arms leave the flag byte-untouched via their early returns. Those are the
// properties 210 was right about, and they are unchanged.
//
// What 229 changed: 210 recorded the retreat by BLANKING Phase to PhaseOldSbUpgrading — a value
// that already means "died before the swap" (it is the empty string, service.go:259). Two distinct
// states shared one wire value, and recoverFromFlag's PreSwap branch rolls back UNCONDITIONALLY, so
// an un-parked attempt was rolled back instead of resumed — the collision 210 existed to prevent.
// The retreat is now recorded in its own field (RetreatedToSourceAt) and Phase is left alone,
// because every phase value describes a position INSIDE an in-flight upgrade and none of them is
// true after a completed retreat. The un-park then removes the whole flag (cmd/install_upgrade.go).
func TestParkServiceRecovery_TruthRestoresFlag_STATBUS210(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	psr := extractFuncBody(t, src, "func (d *Service) parkServiceRecovery(")

	// The retreat is recorded in its OWN field, via the held-flag rewrite.
	rewriteIdx := strings.Index(psr, "f.RetreatedToSourceAt =")
	if rewriteIdx < 0 || !strings.Contains(psr, "d.mutateHeldFlag(func(f *UpgradeFlag)") {
		t.Fatal("STATBUS-210/229: parkServiceRecovery must record the completed retreat on the held flag (f.RetreatedToSourceAt) via mutateHeldFlag on successful restoration")
	}
	// And it must NOT go back to expressing the retreat as a phase: that is the 229 defect.
	if strings.Contains(psr, "f.Phase =") {
		t.Error("STATBUS-229: parkServiceRecovery must NOT write f.Phase. Every phase value describes a position inside an IN-FLIGHT upgrade, so after a completed retreat all of them are lies — and PhaseOldSbUpgrading in particular already means \"died before the swap\", which routes the un-parked attempt into recoverFromFlag's UNCONDITIONAL rollback (service.go:1341). Record the fact in its own field instead")
	}
	// BackupPath must be KEPT — the rewrite must NOT touch f.BackupPath (197's identity key holds).
	if strings.Contains(psr, "f.BackupPath =") {
		t.Error("STATBUS-210: the truth-restoration rewrite must KEEP BackupPath (same attempt's snapshot identity) — it must not assign f.BackupPath")
	}

	// ORDER — the rewrite is on the SUCCESS arm only: it must come AFTER the era-refuse return
	// (appendParkNarrative(id, refusal)) and AFTER the restoration-failure return, so both those
	// arms leave the flag untouched. Proxy: the rewrite must follow the restoreSourceServices call
	// (whose err-branch returns before it).
	restoreIdx := strings.Index(psr, "d.restoreSourceServices(")
	verdictReturnIdx := strings.Index(psr, "d.appendParkNarrative(id, refusal)")
	if restoreIdx < 0 || rewriteIdx < restoreIdx {
		t.Errorf("STATBUS-210: the flag rewrite must be on the restoration-SUCCESS path (after restoreSourceServices@%d), so refusal/failure arms leave the flag untouched — rewrite@%d", restoreIdx, rewriteIdx)
	}
	if verdictReturnIdx < 0 || rewriteIdx < verdictReturnIdx {
		t.Error("STATBUS-210: the era-refuse arm (appendParkNarrative(id, refusal) → return) must precede the flag rewrite so a refused park leaves the marker truthful/untouched")
	}
}
