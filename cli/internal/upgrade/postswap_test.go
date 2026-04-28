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
		PID:        os.Getpid(),
		StartedAt:  time.Now().UTC().Truncate(time.Second),
		InvokedBy:  "test",
		Trigger:    "notify",
		Holder:     HolderService,
		Phase:      FlagPhasePostSwap,
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

	if got.Phase != FlagPhasePostSwap {
		t.Errorf("Phase: got %q, want %q", got.Phase, FlagPhasePostSwap)
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
// to zero values — the Phase="" default means FlagPhasePreSwap, which is
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
	if flag.Phase != FlagPhasePreSwap {
		t.Errorf("legacy Phase: got %q, want empty (FlagPhasePreSwap)", flag.Phase)
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
// d.pendingRecreate through to the on-disk flag so the post-swap resume
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
			if flag.Phase != FlagPhasePreSwap {
				t.Errorf("initial Phase: got %q, want empty (FlagPhasePreSwap)", flag.Phase)
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
	if flag.Phase != FlagPhasePostSwap {
		t.Errorf("Phase: got %q, want %q", flag.Phase, FlagPhasePostSwap)
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
		ID: 100, CommitSHA: "x", CommitTags: []string{"v0-other"}, PID: os.Getpid(),
		Holder: HolderService, Trigger: "notify",
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

// TestRecoverFromFlag_PhaseDiscriminationPresent is a structural guard:
// the HEAD=target self-heal logic MUST be gated behind a Phase check,
// otherwise a post-swap restart (exit-42 handoff, HEAD already at target)
// would mark the row completed while migrate + health-check haven't run
// yet. This test pins the source-level ordering so a future edit that
// removes the branch breaks the test loudly.
func TestRecoverFromFlag_PhaseDiscriminationPresent(t *testing.T) {
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

	phaseIdx := strings.Index(fn, "flag.Phase == FlagPhasePostSwap")
	if phaseIdx < 0 {
		t.Fatal("recoverFromFlag missing Phase discrimination — the HEAD=target branch " +
			"would misclassify post-swap restarts as completed upgrades. Add: " +
			"`if flag.Phase == FlagPhasePostSwap { d.resumePostSwap(ctx, flag); return }` " +
			"BEFORE the git rev-parse HEAD check.")
	}
	headIdx := strings.Index(fn, `"git", "rev-parse", "HEAD"`)
	if headIdx < 0 {
		t.Fatal("recoverFromFlag missing `git rev-parse HEAD` call — test is stale")
	}
	if phaseIdx > headIdx {
		t.Errorf("Phase discrimination must come BEFORE the HEAD=target self-heal branch "+
			"(phaseIdx=%d, headIdx=%d). A post-swap restart has HEAD == target by design, "+
			"so the self-heal branch would fire first and mark the row completed — "+
			"lying about whether migrate/health-check actually ran.", phaseIdx, headIdx)
	}

	// And the branch must route to resumePostSwap, not to anything else.
	branchBody := fn[phaseIdx:]
	if close := strings.Index(branchBody, "\n\t}\n"); close > 0 {
		branchBody = branchBody[:close]
	}
	if !strings.Contains(branchBody, "d.resumePostSwap(ctx, flag)") {
		t.Errorf("Phase discrimination branch must call d.resumePostSwap(ctx, flag). Body:\n%s", branchBody)
	}
}

// TestResumePostSwap_SelfHealOrFailLoud is the structural guard for the
// rc.67 recovery trifecta: resumePostSwap MUST self-heal when containers
// are at the flag's target and MUST fail loudly (return an error) when
// they are not. The pre-rc.67 code auto-rolled back via recoveryRollback
// here — that path produced jo's catastrophic deploy on 2026-04-28 and
// is now removed entirely (see tmp/rc67-recovery-rootcause.md, Findings
// 4 + 7-14).
func TestResumePostSwap_SelfHealOrFailLoud(t *testing.T) {
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
