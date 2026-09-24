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

	// ORDERING + POSITION-CONTRACT PIN: the durable park lands first. A position already
	// established as at-or-past target first proves the serving tier's observed container
	// identity. A running target health-leg stays untouched. Stopped target containers and
	// marker/carrier-proved source containers each get only a bounded in-place start attempt,
	// with a narrative-only result, before returning. It never asks source restoration to re-derive
	// position through its held-closed preconditions. Only the remaining unreadable-position
	// branch may ask for an era verdict, and it must use the route-only contract because target
	// clients may legitimately be live.
	pf := extractFuncBody(t, src, "func (d *Service) parkForDeterministicFailure(")
	parkIdx := strings.Index(pf, "d.parkUpgrade(")
	atTargetIdx := strings.Index(pf, "if obsState == ObservedAlreadyAtNew {")
	recIdx := strings.Index(pf, "d.parkServiceRecovery(ctx, id, restoreTargetSHA, progress, d.StartDatabaseRouteServingMayRun, true)")
	if parkIdx < 0 || atTargetIdx < 0 || recIdx < 0 || parkIdx >= atTargetIdx || atTargetIdx >= recIdx {
		t.Fatalf("deterministic park contract must be park write -> at-target return -> unreadable-position MayRun verdict; parkUpgrade@%d atTarget@%d MayRunRecovery@%d", parkIdx, atTargetIdx, recIdx)
	}
	atTargetBranch := pf[atTargetIdx:recIdx]
	ensureIdx := strings.Index(atTargetBranch, "d.ensureParkedAtNewServingTier(ctx, id, commitSHA, progress)")
	appendIdx := strings.Index(atTargetBranch, "d.appendParkNarrative(id, operabilityNote)")
	returnIdx := strings.Index(atTargetBranch, `return fmt.Errorf("parked on deterministic forward failure: %s", reason)`)
	if ensureIdx < 0 || appendIdx < ensureIdx || returnIdx < appendIdx {
		t.Fatalf("at-target park must observe/start identity-proved existing containers, append a non-empty operability narrative, then return; ensure@%d append@%d return@%d", ensureIdx, appendIdx, returnIdx)
	}
	if !strings.Contains(atTargetBranch, `if operabilityNote != "" {`) {
		t.Error("the running health-leg branch must keep its narrative untouched; append only a non-empty pre-start operability result")
	}
	for _, forbidden := range []string{"parkServiceRecovery", "restoreSourceServices", "StartDatabaseRouteServing", "services held down", "held-closed recovery invariant violated", "compose.Up("} {
		if strings.Contains(atTargetBranch, forbidden) {
			t.Errorf("at-target park must never reach source-era recovery, held-closed routing, or recreation %q", forbidden)
		}
	}
	targetOperability := extractFuncBody(t, src, "func (d *Service) ensureParkedAtNewServingTier(")
	targetStart := extractFuncBody(t, src, "func (d *Service) startExistingTargetServingTier(")
	sourceStart := extractFuncBody(t, src, "func (d *Service) startExistingSourceServingTier(")
	for _, forbidden := range []string{"parkServiceRecovery", "restoreSourceServices", "startSourceApplicationStack", "StartDatabaseRouteServing", "compose.Up("} {
		if strings.Contains(targetOperability, forbidden) || strings.Contains(targetStart, forbidden) || strings.Contains(sourceStart, forbidden) {
			t.Errorf("at-target operability call graph must not contain source recovery or recreate authority %q", forbidden)
		}
	}
	if !strings.Contains(targetOperability, "d.parkedSourceSchemaVerdict(ctx, id)") {
		t.Error("source-era operability must separately prove source-schema compatibility")
	}
	schemaVerdict := extractFuncBody(t, src, "func (d *Service) parkedSourceSchemaVerdict(")
	if !strings.Contains(schemaVerdict, "d.parkEraVerdict(ctx, id, d.StartDatabaseRouteServingMayRun)") || strings.Contains(schemaVerdict, "MustBeStopped") {
		t.Error("at-target source schema proof must reuse parkEraVerdict through the MayRun route, never MustBeStopped")
	}
	for name, body := range map[string]string{"target": targetStart, "source": sourceStart} {
		if !strings.Contains(body, `append([]string{"start"}, sourceServingServices...)`) || !strings.Contains(body, "compose.CommandContext(") {
			t.Errorf("at-target %s-era operability may only use docker compose start for existing app/worker/rest/proxy containers", name)
		}
	}
	if strings.Count(pf, "d.parkServiceRecovery(") != 1 {
		t.Errorf("parkForDeterministicFailure must contain exactly one service-recovery call, only for unreadable position; got %d", strings.Count(pf, "d.parkServiceRecovery("))
	}
	if strings.Contains(pf, "StartDatabaseRouteServingMustBeStopped") {
		t.Error("held-closed route must not be reachable from parkForDeterministicFailure; its source-restoration precondition belongs to rollback-position recovery")
	}

	// HELPER NEVER STOPS ANYTHING (ruling Q4 hard rule): neither the helper nor the restore
	// tail may stop/down services or re-engage maintenance / read-only — they only ever START.
	for _, fn := range []string{
		"func (d *Service) parkServiceRecovery(",
		"func (d *Service) restoreSourceServices(",
		"func (d *Service) startSourceApplicationStack(",
		"func (d *Service) ensureParkedAtNewServingTier(",
		"func (d *Service) startExistingTargetServingTier(",
		"func (d *Service) startExistingSourceServingTier(",
	} {
		body := extractFuncBody(t, src, fn)
		for _, forbidden := range []string{`"stop"`, `"down"`, "QuiesceClients", "setMaintenance(true)", "setDatabaseReadOnly(ctx, true)"} {
			if strings.Contains(body, forbidden) {
				t.Errorf("helper-never-stops: %s must not contain %q — the park-recovery helper may only START services, never stop anything", fn, forbidden)
			}
		}
	}

	// SERVE-PROVEN: restoreSourceServices delegates start + health to the shared
	// source-stack primitive, then lifts the read-only window only after that
	// helper succeeds. The helper itself must contain the real health gate.
	rs := extractFuncBody(t, src, "func (d *Service) restoreSourceServices(")
	stackIdx := strings.Index(rs, "d.startSourceApplicationStack(ctx, progress)")
	// RETARGETED, NOT WEAKENED (STATBUS-266): the terminal OFF now flips through
	// d.liftReadOnlyWindow(), a one-line wrapper that runs the SAME
	// terminalExec(windowOffSQL) and additionally announces success. The property
	// below is unchanged; only the call's spelling moved.
	winIdx := strings.Index(rs, "liftReadOnlyWindow(")
	if stackIdx < 0 || winIdx < 0 || winIdx < stackIdx {
		t.Errorf("serve-proven: the read-only window lift must come AFTER the shared source stack gate in restoreSourceServices — stackGate@%d, windowLift@%d", stackIdx, winIdx)
	}
	stack := extractFuncBody(t, src, "func (d *Service) startSourceApplicationStack(")
	if !strings.Contains(stack, "d.healthCheck(") {
		t.Error("startSourceApplicationStack must execute the ordinary functional health gate before returning success")
	}
	// restoreDatabase is DELIBERATELY skipped (ruling Q2 — the era guard makes it unnecessary).
	if strings.Contains(rs, "restoreDatabase(") {
		t.Error("restoreSourceServices must NOT call restoreDatabase — the era guard proves the DB is at source, so a DB restore is unnecessary and its absence is the mixed-era safeguard (ruling Q2)")
	}
	// ERA-AWARE source convergence: exact Source containers start in place; a
	// coherently-derived Target tier is recreated only after the restored source
	// tree/config proves the desired image identity. Missing or mixed identity refuses.
	if !strings.Contains(stack, `composeArgs = append([]string{"start"}`) || !strings.Contains(stack, "compose.CommandContext(") {
		t.Error("restoreSourceServices must resume already-source-era serving containers in place")
	}
	if !strings.Contains(stack, `composeArgs = append([]string{"-d", "--no-build", "--no-deps"}`) || !strings.Contains(stack, "compose.Up(") {
		t.Error("restoreSourceServices must authoritatively recreate a coherently-derived Target tier from the proven source-era template")
	}
	for _, required := range []string{"sourceServingExpectedImages", "deriveServingEra", "ServingEraSource", "ServingEraTarget", "sourceServingEraUnknownError"} {
		if !strings.Contains(stack, required) {
			t.Errorf("restoreSourceServices source-era proof missing %q", required)
		}
	}

	// appendParkNarrative TWO-ROUTE PIN: source restoration owns its existing refusal/failure
	// notes, while the at-target branch may append only the target operability attempt result.
	psr := extractFuncBody(t, src, "func (d *Service) parkServiceRecovery(")
	inHelper := strings.Count(psr, "d.appendParkNarrative(")
	inTargetBranch := strings.Count(atTargetBranch, "d.appendParkNarrative(")
	inFile := strings.Count(src, "d.appendParkNarrative(")
	if inHelper == 0 || inTargetBranch != 1 || inFile != inHelper+inTargetBranch {
		t.Errorf("appendParkNarrative route pin: calls must be only parkServiceRecovery plus one at-target operability append — found %d in-file, %d source-helper, %d target-branch", inFile, inHelper, inTargetBranch)
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
			// STATBUS-382's pre-destructive source-capture failure parks while the
			// source services are still serving and then removes the flag. There is
			// no machine-state retreat to perform, unlike every post-destructive park.
			if strings.Contains(chunk, "parked on deterministic pre-destructive failure") &&
				strings.Contains(chunk, "d.removeUpgradeFlag()") {
				continue
			}
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
// the parkEraVerdict call (so StartDatabaseRouteServingMustBeStopped's DB-health wait is inside the cover). A
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
		t.Errorf("STATBUS-204: the watchdog ticker must PRECEDE parkEraVerdict — StartDatabaseRouteServingMustBeStopped's ~60s DB-health wait is inside the danger window (ticker@%d must be before verdict@%d)", tickIdx, verdictIdx)
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
	markerFn := extractFuncBody(t, src, "func (d *Service) recordRetreatedToSource(")

	// The retreat is recorded in its OWN field, via the held-flag rewrite.
	rewriteIdx := strings.Index(markerFn, "f.RetreatedToSourceAt =")
	if rewriteIdx < 0 || !strings.Contains(markerFn, "d.mutateHeldFlag(func(f *UpgradeFlag)") {
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
	rewriteCallIdx := strings.Index(psr, "d.recordRetreatedToSource()")
	verdictReturnIdx := strings.Index(psr, "d.appendParkNarrative(id, refusal)")
	if restoreIdx < 0 || rewriteCallIdx < restoreIdx {
		t.Errorf("STATBUS-210: the flag rewrite must be on the restoration-SUCCESS path (after restoreSourceServices@%d), so refusal/failure arms leave the flag untouched — rewrite call@%d", restoreIdx, rewriteCallIdx)
	}
	if verdictReturnIdx < 0 || rewriteCallIdx < verdictReturnIdx {
		t.Error("STATBUS-210: the era-refuse arm (appendParkNarrative(id, refusal) → return) must precede the flag rewrite so a refused park leaves the marker truthful/untouched")
	}
	if !strings.Contains(src, "retreat succeeded but the marker does not record it") || !strings.Contains(markerFn, "return &RetreatMarkerWriteError") || !strings.Contains(psr, "return err") {
		t.Error("B-3: parkServiceRecovery must return the truthful retreat-marker failure instead of logging it and reporting success")
	}
}
