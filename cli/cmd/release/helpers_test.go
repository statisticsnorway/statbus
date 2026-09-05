package releasecmd

import (
	"path/filepath"
	"runtime"
	"testing"
)

// thisRepoFile resolves a repo-relative path from this test's source location.
func thisRepoFile(t *testing.T, relPath string) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// cli/cmd/release/helpers_test.go → up four = repo root.
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
	return filepath.Join(repoRoot, relPath)
}
