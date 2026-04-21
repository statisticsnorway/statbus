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
		if !strings.Contains(inv.TranscriptFormat, "violated") {
			t.Errorf("invariant %q TranscriptFormat missing the anchor word %q "+
				"(support-bundle grep depends on this)", name, "violated")
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
