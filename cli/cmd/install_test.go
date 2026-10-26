package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/invariants"
)

// TestNoSilentNotesInInstall enforces the install-path fail-fast contract
// from the plan's Phase 4: install flow must not emit `Note: ...` or
// `Warning: ...` for conditions that the operator could act on — every
// such condition must either be a named invariant (class=fail-fast, which
// emits the transcript + MarkTerminal and returns a wrapped error) or a
// class=log-only breadcrumb whose primary failure path has already
// terminated the run. Log-only breadcrumbs use log.Printf (which prepends
// a timestamp) rather than fmt.Printf, keeping them outside this gate.
func TestNoSilentNotesInInstall(t *testing.T) {
	pattern := regexp.MustCompile(`fmt\.Printf\("[^"]*(Note|Warning):`)
	files := []string{
		thisRepoFile(t, "cli/cmd/install.go"),
	}
	var violations []string
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		lines := strings.Split(string(data), "\n")
		for i, ln := range lines {
			if pattern.MatchString(ln) {
				violations = append(violations,
					fmt.Sprintf("%s:%d: %s", relPath(f), i+1, strings.TrimSpace(ln)))
			}
		}
	}
	if len(violations) > 0 {
		t.Errorf("install-path files contain %d silent Note/Warning prints "+
			"(Phase 4 must rewrite each as a named invariant):\n  %s",
			len(violations), strings.Join(violations, "\n  "))
	}
}

// TestEveryInvariantHasTriadDocumented walks the runtime registry and
// asserts that every registered invariant has non-empty triad fields
// (Name, Class, SourceLocation, ExpectedToHold, WhyExpected,
// ViolationShape, TranscriptFormat) — i.e., the four-element triad from
// the plan plus the provenance fields. This enforces the "plan ↔ code ↔
// bundle" invariant-triad coupling at build time.
//
// Trivially passes when the registry is empty (Phase 3 state — Phase 4
// is where we first register install-path guards). Gains teeth on each
// subsequent Register() call.
func TestEveryInvariantHasTriadDocumented(t *testing.T) {
	for _, name := range invariants.Names() {
		// Skip the test-only invariants registered by sibling tests in
		// cli/internal/invariants — those are intentionally minimal.
		if strings.HasPrefix(name, "TEST_") {
			continue
		}
		inv, ok := invariants.Get(name)
		if !ok {
			t.Errorf("Names() lists %q but Get(%q) returned !ok", name, name)
			continue
		}
		if inv.Class == "" {
			t.Errorf("invariant %q has empty Class", name)
		}
		if inv.SourceLocation == "" {
			t.Errorf("invariant %q has empty SourceLocation", name)
		}
		if inv.ExpectedToHold == "" {
			t.Errorf("invariant %q has empty ExpectedToHold (first triad field)", name)
		}
		if inv.WhyExpected == "" {
			t.Errorf("invariant %q has empty WhyExpected (second triad field)", name)
		}
		if inv.ViolationShape == "" {
			t.Errorf("invariant %q has empty ViolationShape (third triad field)", name)
		}
		if inv.TranscriptFormat == "" {
			t.Errorf("invariant %q has empty TranscriptFormat (fourth triad field)", name)
		}
		if name != "install_failed_no_row" && !strings.Contains(inv.TranscriptFormat, "violated") {
			t.Errorf("invariant %q TranscriptFormat missing the anchor word %q "+
				"(support-bundle grep depends on this)", name, "violated")
		}
	}
}

// TestRunInstallServiceNeverStartsSynchronously pins both the post-upgrade
// SDNOTIFY rule and STATBUS-432: reconciliation enables the unit but never
// starts or restarts it while install owns the flock. A separate final defer
// submits the lifecycle action with --no-block after completion mutations.
//
// STATBUS-527 moved unit writing + enable into the shared installUpgraderUnit
// (upgrader.go) — the ONE implementation `sb upgrader install` also calls —
// so this test pins the distribution of the guarantee across both files:
// runInstallService never starts/restarts a unit itself, the shared core
// enables but never starts, and the deferred dispatch stays --no-block.
//
// Source-level assertion (rather than a mocked runCmd) keeps the test
// honest about WHERE in the function the gate sits and matches the
// pattern other install-path guards use.
func TestRunInstallServiceNeverStartsSynchronously(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install.go"))
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	body := string(src)
	fn := funcBody(t, body, "func runInstallService(")
	// funcBody stops at the next top-level "func ", but the deferred-action
	// dispatcher follows as a `var ... = func(...)`; cut there so its
	// submitUpgraderAction call is not mistaken for a synchronous start
	// inside runInstallService.
	if i := strings.Index(fn, "\nvar dispatchUpgradeDaemonFinalAction"); i >= 0 {
		fn = fn[:i]
	}

	// The post-upgrade fixup gate: inside the upgrader's own unit, the step
	// must not queue a lifecycle action at all (the daemon hands itself over
	// after the install returns).
	gateIdx := strings.Index(fn, "if insideUnit {")
	if gateIdx < 0 {
		t.Fatal("runInstallService missing the insideUnit (post-upgrade fixup) gate")
	}
	if !strings.Contains(fn, `postUpgradeFixup || os.Getenv("STATBUS_POST_UPGRADE_FIXUP") == "1"`) {
		t.Fatal("insideUnit must be derived from the post-upgrade fixup signals")
	}

	// runInstallService itself never starts or restarts a unit: it enables
	// through the shared core and queues the final action for the deferred
	// --no-block dispatch.
	if strings.Contains(fn, "submitUpgraderAction(") || strings.Contains(fn, "startUpgraderUnit(") || strings.Contains(fn, `"--now"`) {
		t.Errorf("runInstallService must not synchronously start/restart while the install flock is held")
	}
	if !strings.Contains(fn, "installUpgraderUnit(dir, true") {
		t.Error("runInstallService must enable the unit through the shared installUpgraderUnit (upgrader.go)")
	}

	// The shared core enables (never starts); the enable keeps its is-enabled
	// verification so the rune boot-symlink regression stays loud.
	shared, err := os.ReadFile(thisRepoFile(t, "cli/cmd/upgrader.go"))
	if err != nil {
		t.Fatalf("read upgrader.go: %v", err)
	}
	core := funcBody(t, string(shared), "func installUpgraderUnit(")
	if !strings.Contains(core, "enableUpgraderUnit(instance)") {
		t.Error("installUpgraderUnit must enable the unit through enableUpgraderUnit")
	}
	if strings.Contains(core, "submitUpgraderAction(") || strings.Contains(core, `"--now"`) {
		t.Error("installUpgraderUnit must never start the unit — starting is `sb upgrader start` or the deferred final action")
	}
	enableFn := funcBody(t, string(shared), "func enableUpgraderUnit(")
	if !strings.Contains(enableFn, `"is-enabled"`) {
		t.Error("enableUpgraderUnit must verify the boot-enable symlink (is-enabled)")
	}

	// The deferred final dispatch is --no-block (the install flock is held
	// until process exit; a blocking start would deadlock the booting daemon's
	// bounded wait on that lock).
	dispatch := funcBody(t, body, "var dispatchUpgradeDaemonFinalAction = func(")
	if !strings.Contains(dispatch, "submitUpgraderAction(instance, string(action), true)") {
		t.Errorf("final lifecycle dispatch must be submitUpgraderAction(..., noBlock=true)")
	}
}

// thisRepoFile resolves a repo-relative path from the test's source
// location, so the test works regardless of go test's cwd.
func thisRepoFile(t *testing.T, relPath string) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// thisFile = cli/cmd/install_test.go → up two = repo root.
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(thisFile)))
	return filepath.Join(repoRoot, relPath)
}

// relPath returns the repo-relative path from an absolute path, for
// tidy error messages.
func relPath(abs string) string {
	_, thisFile, _, _ := runtime.Caller(0)
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(thisFile)))
	rel, err := filepath.Rel(repoRoot, abs)
	if err != nil {
		return abs
	}
	return rel
}

// ─── Backup-ownership heal step (task #68) ───────────────────────────────

// TestCheckBackupOwnership_NoRoot: backup root missing → returns true
// (nothing to heal). Pins the bare-host case where ~/statbus-backups/
// doesn't exist yet (fresh deploy, no upgrade has run).
func TestCheckBackupOwnership_NoRoot(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("HOME", tmp)
	if !checkBackupOwnershipDone("") {
		t.Error("missing ~/statbus-backups/ should be 'done' (nothing to heal)")
	}
}

// TestCheckBackupOwnership_EmptyRoot: backup root exists but has no
// pre-upgrade-* dirs → returns true. Pins post-prune steady state.
func TestCheckBackupOwnership_EmptyRoot(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("HOME", tmp)
	if err := os.MkdirAll(filepath.Join(tmp, "statbus-backups"), 0o755); err != nil {
		t.Fatal(err)
	}
	if !checkBackupOwnershipDone("") {
		t.Error("empty ~/statbus-backups/ should be 'done'")
	}
}

// TestCheckBackupOwnership_DeployUserOwnedDirs: all pre-upgrade-* dirs
// owned by current user → returns true (no heal needed).
func TestCheckBackupOwnership_DeployUserOwnedDirs(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("HOME", tmp)
	root := filepath.Join(tmp, "statbus-backups")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{
		"pre-upgrade-20260520T120000Z",
		"pre-upgrade-20260521T235611Z",
		"upgrade-logs-20260521T235611Z", // sibling, NOT a pre-upgrade-* — must be ignored
	} {
		if err := os.MkdirAll(filepath.Join(root, name), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if !checkBackupOwnershipDone("") {
		t.Error("dirs owned by current user should be 'done' (no heal needed)")
	}
}

// TestCheckBackupOwnership_IgnoresNonBackupEntries: files + sibling
// dirs that aren't pre-upgrade-* don't trigger heal. Pins the loop's
// HasPrefix gate.
func TestCheckBackupOwnership_IgnoresNonBackupEntries(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("HOME", tmp)
	root := filepath.Join(tmp, "statbus-backups")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	// Non-backup file at root level.
	if err := os.WriteFile(filepath.Join(root, "v2026.03.0-rc.28-pre.tar.gz"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	// Sibling dir (upgrade-logs-*) that's also deploy-owned.
	if err := os.MkdirAll(filepath.Join(root, "upgrade-logs-20260521T235611Z"), 0o755); err != nil {
		t.Fatal(err)
	}
	if !checkBackupOwnershipDone("") {
		t.Error("non-pre-upgrade-* entries should not trigger heal")
	}
}
