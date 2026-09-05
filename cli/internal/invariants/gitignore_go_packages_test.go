package invariants

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// TestNoGoPackageDirectoryIsGitignored_STATBUS352 closes a trap that has bitten
// twice: the inherited Visual Studio .gitignore rule `[Rr]elease/` silently
// swallows any Go package directory named release. cli/internal/release/
// needed a negation; cli/cmd/release/ (STATBUS-352) was created in a worktree
// and its NEW files vanished from a `git add -A` without any error. A missing
// source file is a broken build on the next clone, discovered late.
//
// This test asks git itself (`git check-ignore`) for every directory under
// cli/ that contains a .go file. Any hit is a failure naming the rule, so the
// next new package cannot disappear.
func TestNoGoPackageDirectoryIsGitignored_STATBUS352(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// cli/internal/invariants/x_test.go → up three = repo root.
	repoRoot := filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
	cliRoot := filepath.Join(repoRoot, "cli")

	var dirs []string
	seen := map[string]bool{}
	err := filepath.WalkDir(cliRoot, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if strings.HasSuffix(d.Name(), ".go") {
			dir := filepath.Dir(path)
			if !seen[dir] {
				seen[dir] = true
				rel, _ := filepath.Rel(repoRoot, dir)
				dirs = append(dirs, rel+"/")
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command("git", append([]string{"check-ignore", "-v", "--no-index", "--"}, dirs...)...)
	cmd.Dir = repoRoot
	out, _ := cmd.CombinedOutput() // exit 1 = nothing ignored, which is the pass
	if strings.TrimSpace(string(out)) != "" {
		t.Fatalf("these Go package directories are matched by .gitignore; add a negation next to `!cli/internal/release/`:\n%s", out)
	}
}
