package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"
)

// TestNoSilentNotesInUpgradeService enforces the Phase 5 fail-fast
// contract from the plan: the upgrade service must not emit
// `Note: ...`, `Notice: ...`, or `Warning: ...` via fmt.Printf for
// conditions an operator could act on — every such condition must be a
// named invariant (class=fail-fast, which emits the transcript +
// MarkTerminal and returns a wrapped error) or a class=log-only
// breadcrumb whose primary failure path has already terminated the run.
// Log-only breadcrumbs use log.Printf (timestamp-prefixed) which
// escapes this gate by regex.
func TestNoSilentNotesInUpgradeService(t *testing.T) {
	pattern := regexp.MustCompile(`fmt\.Printf\("[^"]*(Note|Notice|Warning):`)
	files := []string{
		thisRepoFile(t, "cli/internal/upgrade/service.go"),
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
		t.Errorf("upgrade/service.go contains %d silent Note/Notice/Warning prints "+
			"(Phase 5 must rewrite each as a named invariant or a log.Printf "+
			"log-only breadcrumb):\n  %s",
			len(violations), strings.Join(violations, "\n  "))
	}
}

// TestServiceGo_BranchNamesNamespaceFree is the structural guard for
// Item M (plan-rc.66): cli/internal/upgrade/service.go must not
// reference the legacy `statbus/` namespace on local-only state
// branches. Two ref pairs are checked:
//
//   - The pre-upgrade pointer (write + delete + fallback resolver)
//     must use plain `pre-upgrade`, not `statbus/pre-upgrade`.
//   - The current-pointer never appears in service.go (it's an
//     install.sh concern). Asserted as zero hits to catch a future
//     drift.
//
// Defensive: pin the new names AND the absence of the old.
func TestServiceGo_BranchNamesNamespaceFree(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := string(src)

	for _, banned := range []string{
		"statbus/current",
		"statbus/pre-upgrade",
		"statbus/installed", // pre-rc.65 name; should be long gone
	} {
		if strings.Contains(body, banned) {
			t.Errorf("service.go must not reference legacy branch name %q "+
				"(Item M). Use plain `pre-upgrade` / `current`.", banned)
		}
	}

	// Pin the new names by anchoring on the actual call shapes.
	for _, want := range []string{
		`"git", "branch", "-f", "pre-upgrade", "HEAD"`,
		`"git", "branch", "-D", "pre-upgrade"`,
		`"git", "rev-parse", "--verify", "pre-upgrade^{commit}"`,
		`previousVersion = "pre-upgrade"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("service.go missing required call shape after Item M: %q", want)
		}
	}
}

// TestInstallShBranchNamesNamespaceFree mirrors the above for install.sh:
// the three checkout sites must use `current` (not `statbus/current`)
// while the legacy-cleanup `git branch -D statbus/current` lines are
// retained for migrating pre-rc.66 hosts.
func TestInstallShBranchNamesNamespaceFree(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "install.sh"))
	if err != nil {
		t.Fatalf("read install.sh: %v", err)
	}
	body := string(src)

	// Three new-style checkouts, one per code path (edge update,
	// rescue update, fresh clone).
	wantCheckouts := []string{
		`git checkout -B current origin/master`,
		`git checkout -B current "$VERSION"`,
		`git -C "$STATBUS_DIR" checkout -B current "$VERSION"`,
	}
	for _, want := range wantCheckouts {
		if !strings.Contains(body, want) {
			t.Errorf("install.sh missing checkout %q after Item M", want)
		}
	}

	// Both legacy-cleanup lines must be present (idempotent removal of
	// pre-rc.66 statbus/* branches on existing hosts).
	for _, want := range []string{
		`git branch -D statbus/current 2>/dev/null || true`,
		`git branch -D statbus/pre-upgrade 2>/dev/null || true`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("install.sh missing legacy-branch cleanup %q (Item M)", want)
		}
	}

	// Counter-check: no remaining `git checkout` against the legacy
	// name (the cleanup `git branch -D` lines are allowed to mention
	// `statbus/`, but checkouts must not).
	for _, banned := range []string{
		`git checkout -B statbus/current`,
		`git checkout -B statbus/pre-upgrade`,
		`git checkout -B statbus/installed`,
	} {
		if strings.Contains(body, banned) {
			t.Errorf("install.sh still contains legacy checkout %q (Item M); "+
				"only the `git branch -D statbus/...` cleanup lines should mention the legacy namespace.",
				banned)
		}
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
	// thisFile = cli/internal/upgrade/service_test.go → up four = repo root.
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
	return filepath.Join(repoRoot, relPath)
}

// relPath returns the repo-relative path from an absolute path, for
// tidy error messages.
func relPath(abs string) string {
	_, thisFile, _, _ := runtime.Caller(0)
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
	rel, err := filepath.Rel(repoRoot, abs)
	if err != nil {
		return abs
	}
	return rel
}
