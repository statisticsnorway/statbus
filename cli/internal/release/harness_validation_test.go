package release

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

func realRunnerSource(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	root := filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
	b, err := os.ReadFile(filepath.Join(root, "test", "install-recovery", "run.sh"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func gitFixture(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", testgit.Args(args...)...)
	cmd.Dir = dir
	cmd.Env = testgit.Env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func writeFile(t *testing.T, dir, rel, content string, mode os.FileMode) {
	t.Helper()
	full := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
}

// harnessRepo commits a faithful harness tree: the REAL runner, two default
// scenarios, one excluded (HARNESS_SKIP_DEFAULT) sibling, one arc.
func harnessRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	gitFixture(t, dir, "init", "-q")
	writeFile(t, dir, "test/install-recovery/run.sh", realRunnerSource(t), 0o755)
	writeFile(t, dir, "test/install-recovery/scenarios/scenario-a.sh", "#!/bin/bash\necho a\n", 0o755)
	writeFile(t, dir, "test/install-recovery/scenarios/scenario-b.sh", "#!/bin/bash\necho b\n", 0o755)
	writeFile(t, dir, "test/install-recovery/scenarios/known-red.sh", "#!/bin/bash\n# HARNESS_SKIP_DEFAULT: deliberate\necho red\n", 0o755)
	writeFile(t, dir, "test/install-recovery/arcs/working-arc.sh", "#!/bin/bash\necho arc\n", 0o755)
	gitFixture(t, dir, "add", ".")
	gitFixture(t, dir, "commit", "-q", "-m", "base")
	return dir
}

func TestValidateHarnessDomainAt_RealRunnerPassesAndDomainMatches_STATBUS352(t *testing.T) {
	dir := harnessRepo(t)
	head := gitFixture(t, dir, "rev-parse", "HEAD")
	if err := ValidateHarnessDomainAt(dir, head); err != nil {
		t.Fatalf("a clean harness tree must validate: %v", err)
	}
}

// The reproduction from the Work A review: an EXCLUDED sibling gains a
// forbidden fabrication call. Every default scenario is unchanged, so the old
// evaluator would have said "covered". The target commit's own runner refuses,
// and so must the shared evaluator's prerequisite.
func TestValidateHarnessDomainAt_ForbiddenExcludedSiblingIsRefused_STATBUS352(t *testing.T) {
	dir := harnessRepo(t)
	writeFile(t, dir, "test/install-recovery/scenarios/known-red.sh",
		"#!/bin/bash\n# HARNESS_SKIP_DEFAULT: deliberate\nfabricate_forbidden_state \"$VM\"\n", 0o755)
	gitFixture(t, dir, "add", ".")
	gitFixture(t, dir, "commit", "-q", "-m", "forbidden sibling")
	head := gitFixture(t, dir, "rev-parse", "HEAD")

	err := ValidateHarnessDomainAt(dir, head)
	if err == nil || !strings.Contains(err.Error(), "FABRICATION") {
		t.Fatalf("a forbidden construct in an excluded sibling must fail structural validation with the runner's own diagnostic; got %v", err)
	}
	// The working tree must not have been touched: validation reads the commit.
	if out := gitFixture(t, dir, "status", "--porcelain"); out != "" {
		t.Fatalf("validation mutated the working tree:\n%s", out)
	}
}

func TestValidateHarnessDomainAt_ValidatesTheCommitNotTheWorkingTree_STATBUS352(t *testing.T) {
	dir := harnessRepo(t)
	head := gitFixture(t, dir, "rev-parse", "HEAD")
	// Dirty the working tree with a forbidden construct that is NOT committed.
	writeFile(t, dir, "test/install-recovery/scenarios/scenario-a.sh", "#!/bin/bash\nfabricate_x ()\n", 0o755)
	if err := ValidateHarnessDomainAt(dir, head); err != nil {
		t.Fatalf("validation must read the committed tree, not the dirty working tree: %v", err)
	}
}

func TestValidateHarnessDomainAt_MissingRunnerAndEmptyDomainAreErrors_STATBUS352(t *testing.T) {
	dir := t.TempDir()
	gitFixture(t, dir, "init", "-q")
	writeFile(t, dir, "test/install-recovery/scenarios/scenario-a.sh", "#!/bin/bash\n", 0o755)
	gitFixture(t, dir, "add", ".")
	gitFixture(t, dir, "commit", "-q", "-m", "no runner")
	head := gitFixture(t, dir, "rev-parse", "HEAD")
	if err := ValidateHarnessDomainAt(dir, head); err == nil || !strings.Contains(err.Error(), "run.sh") {
		t.Fatalf("a commit without a runner cannot be validated; got %v", err)
	}

	writeFile(t, dir, "test/install-recovery/run.sh", realRunnerSource(t), 0o755)
	writeFile(t, dir, "test/install-recovery/scenarios/scenario-a.sh", "#!/bin/bash\n# HARNESS_SKIP_DEFAULT\n", 0o755)
	gitFixture(t, dir, "add", ".")
	gitFixture(t, dir, "commit", "-q", "-m", "all excluded")
	head = gitFixture(t, dir, "rev-parse", "HEAD")
	if err := ValidateHarnessDomainAt(dir, head); err == nil {
		t.Fatal("an all-excluded (empty) domain must be an error, never validated")
	}
}

func TestValidateHarnessDomainAt_RunnerAndEvaluatorDomainMustAgree_STATBUS352(t *testing.T) {
	dir := harnessRepo(t)
	// A runner that lies about the domain (emits a scenario the tree does not
	// hold) is a disagreement between the validator and the evaluator.
	writeFile(t, dir, "test/install-recovery/run.sh", "#!/bin/bash\necho scenario-a\necho phantom\n", 0o755)
	gitFixture(t, dir, "add", ".")
	gitFixture(t, dir, "commit", "-q", "-m", "lying runner")
	head := gitFixture(t, dir, "rev-parse", "HEAD")
	if err := ValidateHarnessDomainAt(dir, head); err == nil || !strings.Contains(err.Error(), "disagree") {
		t.Fatalf("runner/evaluator domain disagreement must be an error; got %v", err)
	}
}
