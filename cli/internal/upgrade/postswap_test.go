package upgrade

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

// Tests for the Option C "principled restart-early" handoff:
//   - UpgradeFlag struct carries Phase + Recreate + BackupPath across the
//     exit-42 restart so the new binary's recoverFromFlag can resume.
//   - writeUpgradeFlag persists the Recreate bit passed by executeUpgrade.
//   - updateFlagPostSwap rewrites the on-disk JSON in place and keeps the
//     flock held (another acquirer must still be blocked).
//   - recoverFromFlag branches on Phase BEFORE the HEAD=target self-heal
//     logic, so a post-swap restart does NOT falsely mark the row
//     completed.
//
// End-to-end resume coverage (actual post-swap DB handoff) requires a
// live postgres + systemd restart and lives in the upgrade integration
// smoke tests, not here.

// TestUpgradeFlagJSONRoundTrip_PostSwap verifies the new fields (Phase,
// Recreate, BackupPath) serialise and deserialise cleanly.
func TestUpgradeFlagJSONRoundTrip_PostSwap(t *testing.T) {
	original := UpgradeFlag{
		ID:         42,
		CommitSHA:  "abc123def456",
		CommitTags: []string{"v0.0.0-rc.test"},
		StartedAt:  time.Now().UTC().Truncate(time.Second),
		InvokedBy:  "test",
		Trigger:    "notify",
		Holder:     HolderService,
		Phase:      PhaseNewSbSwapped,
		Recreate:   true,
		BackupPath: "/home/x/statbus-backups/pre-upgrade-20260422T010203Z",
	}

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var got UpgradeFlag
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if got.Phase != PhaseNewSbSwapped {
		t.Errorf("Phase: got %q, want %q", got.Phase, PhaseNewSbSwapped)
	}
	if !got.Recreate {
		t.Errorf("Recreate: got false, want true")
	}
	if got.BackupPath != original.BackupPath {
		t.Errorf("BackupPath: got %q, want %q", got.BackupPath, original.BackupPath)
	}
}

// TestUpgradeFlagJSONLegacy_OmitsOptionalFields verifies that legacy
// pre-Option-C flag files (no phase/recreate/backup_path keys) round-trip
// to zero values — the Phase="" default means PhaseOldSbUpgrading, which is
// the pre-existing semantic.
func TestUpgradeFlagJSONLegacy_OmitsOptionalFields(t *testing.T) {
	legacyJSON := []byte(`{
		"id": 10,
		"commit_sha": "legacy",
		"display_name": "v0.0.0-legacy",
		"pid": 999,
		"invoked_by": "legacy",
		"trigger": "notify",
		"holder": "service"
	}`)

	var flag UpgradeFlag
	if err := json.Unmarshal(legacyJSON, &flag); err != nil {
		t.Fatalf("unmarshal legacy: %v", err)
	}
	if flag.Phase != PhaseOldSbUpgrading {
		t.Errorf("legacy Phase: got %q, want empty (PhaseOldSbUpgrading)", flag.Phase)
	}
	if flag.Recreate {
		t.Errorf("legacy Recreate: got true, want false")
	}
	if flag.BackupPath != "" {
		t.Errorf("legacy BackupPath: got %q, want empty", flag.BackupPath)
	}

	// And serialising a legacy-shaped flag back out must NOT emit the
	// optional keys — omitempty keeps the file tidy for pre-1.1 operators
	// who SSH in to inspect.
	out, err := json.Marshal(flag)
	if err != nil {
		t.Fatalf("re-marshal: %v", err)
	}
	s := string(out)
	for _, key := range []string{`"phase"`, `"recreate"`, `"backup_path"`} {
		if strings.Contains(s, key) {
			t.Errorf("omitempty broken: legacy flag re-serialised contains %s: %s", key, s)
		}
	}
}

// TestWriteUpgradeFlag_PersistsRecreate verifies executeUpgrade can hand
// the recreate intent through to the on-disk flag so the post-swap resume
// replays the --recreate branch identically.
func TestWriteUpgradeFlag_PersistsRecreate(t *testing.T) {
	for _, recreate := range []bool{false, true} {
		t.Run(map[bool]string{false: "false", true: "true"}[recreate], func(t *testing.T) {
			projDir := t.TempDir()
			if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
				t.Fatal(err)
			}
			d := &Service{projDir: projDir}
			if err := d.writeUpgradeFlag(7, "sha7", []string{"v0.0.0-test"}, "test", string(TriggerService), recreate); err != nil {
				t.Fatalf("writeUpgradeFlag: %v", err)
			}
			defer d.removeUpgradeFlag()

			data, err := os.ReadFile(d.flagPath())
			if err != nil {
				t.Fatalf("read flag: %v", err)
			}
			var flag UpgradeFlag
			if err := json.Unmarshal(data, &flag); err != nil {
				t.Fatalf("unmarshal flag: %v", err)
			}
			if flag.Recreate != recreate {
				t.Errorf("Recreate: got %v, want %v", flag.Recreate, recreate)
			}
			if flag.Phase != PhaseOldSbUpgrading {
				t.Errorf("initial Phase: got %q, want empty (PhaseOldSbUpgrading)", flag.Phase)
			}
			if flag.BackupPath != "" {
				t.Errorf("initial BackupPath: got %q, want empty", flag.BackupPath)
			}
		})
	}
}

// TestUpdateFlagPostSwap_RewritesInPlace verifies the helper stamps
// Phase=post_swap + BackupPath on the same fd, without releasing the
// flock. Another actor trying to acquire must still be blocked afterwards.
func TestUpdateFlagPostSwap_RewritesInPlace(t *testing.T) {
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(99, "sha99", []string{"v0.0.0-stamp"}, "test", string(TriggerService), true); err != nil {
		t.Fatalf("writeUpgradeFlag: %v", err)
	}
	defer d.removeUpgradeFlag()

	backup := filepath.Join(projDir, "backup-dir")
	if err := d.updateFlagPostSwap(backup); err != nil {
		t.Fatalf("updateFlagPostSwap: %v", err)
	}

	data, err := os.ReadFile(d.flagPath())
	if err != nil {
		t.Fatalf("read flag: %v", err)
	}
	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		t.Fatalf("unmarshal flag: %v", err)
	}
	if flag.Phase != PhaseNewSbSwapped {
		t.Errorf("Phase: got %q, want %q", flag.Phase, PhaseNewSbSwapped)
	}
	if flag.BackupPath != backup {
		t.Errorf("BackupPath: got %q, want %q", flag.BackupPath, backup)
	}
	// Pre-existing fields preserved.
	if flag.ID != 99 || flag.CommitSHA != "sha99" || !flag.Recreate {
		t.Errorf("updateFlagPostSwap dropped pre-existing fields: %+v", flag)
	}

	// Flock must still be held: a second acquirer in the same process
	// gets a contention error (non-blocking LOCK_NB).
	if _, err := acquireFlock(projDir, UpgradeFlag{
		ID: 100, CommitSHA: "x", CommitTags: []string{"v0-other"}, Holder: HolderService, Trigger: "notify",
	}); err == nil {
		t.Errorf("expected second acquireFlock to fail (flock still held after updateFlagPostSwap)")
	}
}

// TestUpdateFlagPostSwap_RejectsNoFd guards the precondition: if the
// service never acquired the flag, updateFlagPostSwap must not silently
// succeed — that would write a phantom file without a held flock.
func TestUpdateFlagPostSwap_RejectsNoFd(t *testing.T) {
	d := &Service{projDir: t.TempDir()}
	if err := d.updateFlagPostSwap("/tmp/x"); err == nil {
		t.Error("expected updateFlagPostSwap on a Service without flagLock to error")
	}
}

// TestRecoverFromFlag_PhaseRoutingAndObservedStateFirst is the structural
// guard for recoverFromFlag's routing after STATBUS-039:
//
//  1. Every produced phase has an explicit branch (PreSwap "", PostSwap,
//     Resuming) and PostSwap routes to resumePostSwap — a post-swap restart
//     (exit-42 handoff) must resume the pipeline, never be misclassified.
//  2. The pre-039 HEAD=target self-heal segment is GONE from recoverFromFlag
//     (it was unreachable for every producible phase, and its headSHA
//     discriminator misclassified harness/checkout states). The function
//     must NOT regrow a `git rev-parse HEAD` discriminator — observed state
//     (verifyUpgradeObservedStateEx) is the only direction oracle.
//  3. In the Resuming branch, observed state is consulted BEFORE
//     recoveryRollback can run (rule 1: forward when logically possible —
//     a died attempt is not impossibility). The pre-039 one-shot latch
//     rolled back unconditionally: one transient failure, no second chance,
//     a restore behind it (the rune id=187 shape).
//  4. An unknown phase fails LOUD (FLAG_PHASE_UNKNOWN) instead of guessing.
func TestRecoverFromFlag_PhaseRoutingAndObservedStateFirst(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}

	// Extract the recoverFromFlag body.
	body := string(src)
	start := strings.Index(body, "func (d *Service) recoverFromFlag(")
	if start < 0 {
		t.Fatal("recoverFromFlag not found in service.go")
	}
	// Scan forward to the matching closing brace at column 0.
	rest := body[start:]
	end := regexp.MustCompile(`(?m)^}\n`).FindStringIndex(rest)
	if end == nil {
		t.Fatal("recoverFromFlag closing brace not found")
	}
	fn := rest[:end[1]]

	// (1) Phase discrimination present; PostSwap routes to resumePostSwap.
	phaseIdx := strings.Index(fn, "flag.Phase == PhaseNewSbSwapped")
	if phaseIdx < 0 {
		t.Fatal("recoverFromFlag missing the PostSwap phase branch — a post-swap restart would be misrouted")
	}
	postSwapBranch := fn[phaseIdx:]
	if close := strings.Index(postSwapBranch, "\n\t}\n"); close > 0 {
		postSwapBranch = postSwapBranch[:close]
	}
	if !strings.Contains(postSwapBranch, "d.resumePostSwap(ctx, flag)") {
		t.Errorf("PostSwap branch must call d.resumePostSwap(ctx, flag). Body:\n%s", postSwapBranch)
	}

	// (2) The HEAD=target self-heal segment must stay deleted.
	if strings.Contains(fn, `"git", "rev-parse", "HEAD"`) {
		t.Error("recoverFromFlag must NOT contain a git rev-parse HEAD discriminator — " +
			"the dead HEAD=target self-heal segment was removed (STATBUS-039); " +
			"direction is decided by verifyUpgradeObservedStateEx in the phase branches, not by HEAD comparison")
	}

	// (3) Resuming branch: observed state BEFORE rollback.
	resumingIdx := strings.Index(fn, "flag.Phase == PhaseNewSbUpgrading")
	if resumingIdx < 0 {
		t.Fatal("recoverFromFlag missing the Resuming phase branch")
	}
	resumingBranch := fn[resumingIdx:]
	if nextBranch := strings.Index(resumingBranch, "flag.Phase == PhaseNewSbSwapped"); nextBranch > 0 {
		resumingBranch = resumingBranch[:nextBranch]
	}
	obsIdx := strings.Index(resumingBranch, "verifyUpgradeObservedStateEx")
	rbIdx := strings.Index(resumingBranch, "recoveryRollback")
	if obsIdx < 0 {
		t.Fatal("Resuming branch must consult verifyUpgradeObservedStateEx (STATBUS-039 rule 1: ground truth decides direction before any rollback)")
	}
	if rbIdx < 0 {
		t.Fatal("Resuming branch must retain the positively-behind rollback path (recoveryRollback)")
	}
	if obsIdx > rbIdx {
		t.Errorf("ground truth must be consulted BEFORE recoveryRollback in the Resuming branch (obsIdx=%d, rbIdx=%d) — "+
			"otherwise one died resume latches the next recovery into a restore over a possibly at-target box", obsIdx, rbIdx)
	}
	if !strings.Contains(resumingBranch, "d.resumePostSwap(ctx, flag)") {
		t.Error("Resuming branch must route the at-target/unverifiable verdicts FORWARD via d.resumePostSwap")
	}

	// (4) Unknown phase fails loud.
	if !strings.Contains(fn, "FLAG_PHASE_UNKNOWN") {
		t.Error("recoverFromFlag must fail loud (FLAG_PHASE_UNKNOWN) on a phase outside the produced set")
	}
}

// TestResumePostSwap_SelfHealContinueOrFailLoud is the structural guard
// for the rc.67 recovery trifecta. resumePostSwap takes ONE of three
// paths when handling a flagged in-flight upgrade after process restart:
//
//  1. self-heal: containers ARE at flag target → mark row completed
//  2. continuation: containers stopped/missing AND running binary IS at
//     flag target → fall through to applyPostSwap (normal mid-pipeline
//     resume after the binary swap that triggered exit-42)
//  3. category-3 fail-loud: containers stopped/missing AND running binary
//     is NOT at flag target (an unrelated install advanced past) → return
//     a category-3 error
//
// The pre-rc.67 code auto-rolled back via recoveryRollback in case (3) —
// that path produced jo's catastrophic deploy on 2026-04-28 and is now
// removed entirely (tmp/rc67-recovery-rootcause.md, Findings 4 + 7-14).
//
// rc.67's first cut conflated cases (2) and (3) into a single fail-loud
// path, which wedged dev's normal forward upgrade post-swap with
// "containers do not match flag target [app: old version not running, new version not started yet worker: old version not running, new version not started yet
// rest: old version not running, new version not started yet]". The fix discriminates on d.binaryCommit vs
// flag.CommitSHA.
func TestResumePostSwap_SelfHealContinueOrFailLoud(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := string(src)
	start := strings.Index(body, "func (d *Service) resumePostSwap(")
	if start < 0 {
		t.Fatal("resumePostSwap not found in service.go")
	}
	rest := body[start:]
	end := regexp.MustCompile(`(?m)^}\n`).FindStringIndex(rest)
	if end == nil {
		t.Fatal("resumePostSwap closing brace not found")
	}
	fn := rest[:end[1]]

	probeIdx := strings.Index(fn, "d.containersAtFlagTarget(ctx, flag)")
	if probeIdx < 0 {
		t.Fatal("resumePostSwap missing self-heal probe call. Add: " +
			"`if ok, mismatched := d.containersAtFlagTarget(ctx, flag); ok { ... }`")
	}

	// The self-heal branch must mark state=completed (matching the
	// existing LabelCompletedSelfHeal pattern) and remove the flag.
	for _, want := range []string{
		"state = 'completed'",
		"LabelCompletedSelfHeal",
		"os.Remove(d.flagPath())",
	} {
		if !strings.Contains(fn, want) {
			t.Errorf("self-heal branch missing required token %q. Body:\n%s", want, fn)
		}
	}

	// rc.67 trifecta: NO auto-rollback in resumePostSwap. Both the
	// helper and the heavyweight rollback driver must be absent here.
	// Strip line comments first — the function body still mentions both
	// names in a "removed in rc.67" comment for historical context, and
	// that shouldn't fail the structural guard.
	codeOnly := stripLineComments(fn)
	for _, banned := range []string{
		"needsPostSwapRollback",
		"recoveryRollback",
	} {
		if strings.Contains(codeOnly, banned) {
			t.Errorf("resumePostSwap must not call %q (rc.67 trifecta: containers-not-at-flag-target is "+
				"category-3, fail loudly with a returned error instead of auto-rolling-back)", banned)
		}
	}

	// The mismatch branch must surface a category-3 error rather than
	// silently masking the divergence. Match on the unique phrase from
	// the error message we now produce.
	if !strings.Contains(fn, "category-3") {
		t.Error("resumePostSwap mismatch branch must return a category-3 error " +
			"(per the recovery trifecta) — looked for the literal token \"category-3\" " +
			"in the function body and didn't find it.")
	}

	// rc.67 follow-up (case 2 vs case 3 discrimination): the mismatch
	// branch MUST consult d.binaryCommit before deciding fail-loud vs
	// continue. Without this discriminator, every normal forward upgrade
	// fails post-swap because containers are stopped mid-pipeline by
	// design.
	if !strings.Contains(codeOnly, "d.binaryCommit") {
		t.Error("resumePostSwap mismatch branch must check d.binaryCommit vs flag.CommitSHA " +
			"to discriminate normal mid-pipeline state (binary at flag target → continue) " +
			"from genuine category-3 divergence (binary != flag target → fail loud).")
	}
}

// stripLineComments removes everything from `//` to end-of-line on each
// line of src, returning code-only text. Used by structural-guard tests
// that need to forbid a token in active code while allowing it in a
// "removed-in-rcXX" historical comment.
//
// Naive — does not understand strings or rune literals. Sufficient for
// the structural guards that scan idiomatic Go in this package.
func stripLineComments(src string) string {
	var b strings.Builder
	for _, line := range strings.Split(src, "\n") {
		if i := strings.Index(line, "//"); i >= 0 {
			line = line[:i]
		}
		b.WriteString(line)
		b.WriteByte('\n')
	}
	return b.String()
}

// TestPostSwapFailure_ObservedStateBeforeRollback is the structural guard for
// STATBUS-039 rule 1 at the applyPostSwap failure chokepoint: every step
// failure routes through postSwapFailure, and postSwapFailure must consult
// observed state (verifyUpgradeObservedStateEx) BEFORE d.rollback can run.
// Only a POSITIVELY-behind verdict may restore; already-at-new and unverifiable
// verdicts record the failure non-terminally and retry forward on the next
// recovery pass. Without this ordering, one transient health blip on an
// already-at-new box (rune id=187: everything at target except a lagging proxy)
// routes into a snapshot restore — destroying anything written past the
// maintenance-off commit point.
func TestPostSwapFailure_ObservedStateBeforeRollback(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) postSwapFailure(")

	obsIdx := strings.Index(body, "verifyUpgradeObservedStateEx")
	rbIdx := strings.Index(body, "d.rollback(")
	if obsIdx < 0 {
		t.Fatal("postSwapFailure must consult verifyUpgradeObservedStateEx (STATBUS-039 rule 1)")
	}
	if rbIdx < 0 {
		t.Fatal("postSwapFailure must retain the positively-behind rollback path (d.rollback)")
	}
	if obsIdx > rbIdx {
		t.Errorf("ground truth must be consulted BEFORE d.rollback in postSwapFailure (obsIdx=%d, rbIdx=%d)", obsIdx, rbIdx)
	}
	// The non-Behind verdicts must return WITHOUT rollback: the early
	// return goes through recordInProgressFailure (non-terminal, row stays
	// in_progress for the forward retry).
	if !strings.Contains(body, "recordInProgressFailure") {
		t.Error("postSwapFailure's at-target/unverifiable branch must record the failure non-terminally (recordInProgressFailure) and keep the row in_progress for the forward retry")
	}
	if !strings.Contains(body, "ObservedCannotReachNew") {
		t.Error("postSwapFailure must discriminate on ObservedCannotReachNew — restore only on a POSITIVE behind verdict, never under uncertainty")
	}
}

// TestRestoreDatabase_IdentityKeyed_NoRecencyScan pins the identity contract
// at the restore source itself: restoreDatabase takes the recorded snapshot
// path as a parameter and contains NO directory scan (the former
// pickLatestBackup recency selector is gone). A recency scan here is the
// one place another upgrade's backup could be restored (STATBUS-039/-031).
func TestRestoreDatabase_IdentityKeyed_NoRecencyScan(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/exec.go"))
	if err != nil {
		t.Fatalf("read exec.go: %v", err)
	}
	s := string(src)
	// The function and its call sites must stay deleted (historical mentions
	// in comments are fine — they explain WHY the contract exists).
	for _, forbidden := range []string{"func (d *Service) pickLatestBackup", "d.pickLatestBackup("} {
		if strings.Contains(s, forbidden) {
			t.Errorf("%q must stay deleted — restore selection by recency is forbidden (identity-keyed restore, STATBUS-039/-031)", forbidden)
		}
	}
	body := extractFuncBody(t, s, "func (d *Service) restoreDatabase(")
	for _, scan := range []string{"os.ReadDir", "filepath.Glob", "sort.Strings"} {
		if strings.Contains(body, scan) {
			t.Errorf("restoreDatabase must not scan the backup root (%s found) — it consumes ONLY the recorded path parameter", scan)
		}
	}
	if !strings.Contains(body, "backupPath string") && !strings.Contains(s, "func (d *Service) restoreDatabase(progress *ProgressLog, backupPath string)") {
		t.Error("restoreDatabase must take the recorded snapshot path as a parameter (identity-keyed)")
	}
}

// TestRecoveryRollback_FlockGateBeforeDestructiveWork is the structural
// guard for STATBUS-039 review finding 3 (fleet-wide corruption fix):
// recoveryRollback must acquire the upgrade flock BEFORE any destructive
// work — install's inline recovery holds neither the install flag nor the
// daemon advisory lock when it reaches here, and a concurrently respawned
// service's recovery is equally lock-free, so without the gate two
// rsync --delete restores can hit the same DB volume at once. rollback()
// itself must stay acquire-free: its in-process callers (resumePostSwap →
// applyPostSwap → postSwapFailure) already hold the flock, and a second
// flock on the same file fails even within one process.
func TestRecoveryRollback_FlockGateBeforeDestructiveWork(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	s := string(src)

	rr := extractFuncBody(t, s, "func (d *Service) recoveryRollback(")
	gateIdx := strings.Index(rr, "acquireFlock")
	workIdx := strings.Index(rr, "d.rollback(")
	if gateIdx < 0 {
		t.Fatal("recoveryRollback must acquire the upgrade flock (the destructive-work mutex) — finding 3")
	}
	if workIdx < 0 {
		t.Fatal("recoveryRollback must invoke d.rollback")
	}
	if gateIdx > workIdx {
		t.Errorf("the flock gate must come BEFORE d.rollback in recoveryRollback (gate=%d, rollback=%d)", gateIdx, workIdx)
	}
	// The loser must yield: a return on acquire failure, before rollback.
	if !strings.Contains(rr, "yield") && !strings.Contains(rr, "Yield") {
		t.Error("recoveryRollback's acquire-failure branch must YIELD (return without destructive work)")
	}
	// The in-process path's guard: already-held flock fails fast.
	if !strings.Contains(rr, "d.flagLock != nil") {
		t.Error("recoveryRollback must fail fast when the flock is already held in-process (mis-wiring guard)")
	}

	// rollback() itself stays acquire-free.
	rb := extractFuncBody(t, s, "func (d *Service) rollback(")
	if strings.Contains(rb, "acquireFlock") {
		t.Error("rollback() must NOT acquire the flock — its in-process callers already hold it; the gate lives in recoveryRollback only")
	}
}

// TestRemoveUpgradeFlag_AtomicDispositions pins the F4 TOCTOU hardening
// (STATBUS-039): every branch of removeUpgradeFlag unlinks the flag file
// only WHILE HOLDING its flock, so a concurrent acquirer's fresh mutex
// file can never be the one removed (no check-then-remove µs windows).
func TestRemoveUpgradeFlag_AtomicDispositions(t *testing.T) {
	t.Run("owned-lock: removed and released", func(t *testing.T) {
		projDir := t.TempDir()
		if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
			t.Fatal(err)
		}
		d := &Service{projDir: projDir}
		if err := d.writeUpgradeFlag(7, "sha7", []string{"v0.0.0-t"}, "test", string(TriggerService), false); err != nil {
			t.Fatalf("writeUpgradeFlag: %v", err)
		}
		d.removeUpgradeFlag()
		if _, err := os.Stat(d.flagPath()); !os.IsNotExist(err) {
			t.Errorf("flag file must be removed; stat err=%v", err)
		}
		// Lock must be released: a fresh acquire succeeds.
		lock, err := acquireFlock(projDir, UpgradeFlag{ID: 8, CommitSHA: "x", Holder: HolderService, Trigger: "notify"})
		if err != nil {
			t.Fatalf("acquire after removeUpgradeFlag must succeed: %v", err)
		}
		lock.Close()
	})

	t.Run("ghost: flock-free file removed", func(t *testing.T) {
		projDir := t.TempDir()
		if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
			t.Fatal(err)
		}
		d := &Service{projDir: projDir}
		if err := os.WriteFile(d.flagPath(), []byte(`{"id":9,"holder":"service"}`), 0644); err != nil {
			t.Fatal(err)
		}
		d.removeUpgradeFlag()
		if _, err := os.Stat(d.flagPath()); !os.IsNotExist(err) {
			t.Errorf("ghost flag (flock free) must be removed; stat err=%v", err)
		}
	})

	t.Run("held-by-another: left in place", func(t *testing.T) {
		projDir := t.TempDir()
		if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
			t.Fatal(err)
		}
		holder, err := acquireFlock(projDir, UpgradeFlag{ID: 10, CommitSHA: "h", Holder: HolderService, Trigger: "notify"})
		if err != nil {
			t.Fatalf("holder acquire: %v", err)
		}
		defer holder.Close()

		d := &Service{projDir: projDir} // no lock of its own
		d.removeUpgradeFlag()
		if _, err := os.Stat(d.flagPath()); err != nil {
			t.Errorf("flag held by a live actor must be LEFT in place; stat err=%v", err)
		}
	})

	t.Run("absent: no file manufactured", func(t *testing.T) {
		projDir := t.TempDir()
		if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
			t.Fatal(err)
		}
		d := &Service{projDir: projDir}
		d.removeUpgradeFlag()
		if _, err := os.Stat(d.flagPath()); !os.IsNotExist(err) {
			t.Errorf("removeUpgradeFlag on an absent flag must not create one; stat err=%v", err)
		}
	})
}
