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
