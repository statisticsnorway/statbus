package testgit

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The race itself cannot be reproduced on demand — it needs a runner to spawn a
// background process at the moment Go's cleanup walks the directory, and it did
// not recur on the very next runner. So the tests below do NOT try to force the
// symptom. They prove the MECHANISM behaviourally: that a git command run
// through this package genuinely sees maintenance disabled and genuinely does
// not see the machine's configuration, EVEN WHEN a hostile global config says
// the opposite.
//
// That is the strongest available check, and it is the one that would catch a
// regression: the plausible way this protection dies is someone dropping a flag
// or a helper bypassing the package, not git changing what gc.auto means.

// hostileGlobalConfig writes a global git config that switches ON exactly what
// this package exists to switch off, and points git at it. It is the stand-in
// for a runner whose machine-level config we do not control.
func hostileGlobalConfig(t *testing.T) {
	t.Helper()
	cfg := filepath.Join(t.TempDir(), "hostile.gitconfig")
	body := "[gc]\n\tauto = 1\n\tautoDetach = true\n" +
		"[maintenance]\n\tauto = true\n" +
		"[core]\n\tfsmonitor = true\n" +
		"[commit]\n\tgpgsign = true\n" +
		"[init]\n\tdefaultBranch = not-our-branch\n" +
		// Settings the isolation does NOT name explicitly. These are what the
		// global-config cut-off actually protects: the -c flags above can only
		// override keys someone thought to list, and the dangerous ones are the
		// keys nobody thought of. core.hooksPath is the sharpest — a machine
		// pointing it at a directory of hooks would run them inside every
		// fixture this repo builds.
		"[core]\n\tautocrlf = true\n\thooksPath = /tmp/hostile-hooks\n"
	if err := os.WriteFile(cfg, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_CONFIG_GLOBAL", cfg)
}

// TestIsolationBeatsAHostileGlobalConfig is the behavioural proof. Each setting
// is read back through `git config --get` from a git process launched exactly
// the way the helpers launch one — so it measures what git ACTUALLY resolved,
// not what this package intended.
func TestIsolationBeatsAHostileGlobalConfig(t *testing.T) {
	hostileGlobalConfig(t)
	dir := t.TempDir()

	run := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", Args(args...)...)
		cmd.Dir = dir
		cmd.Env = Env()
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	run("init", "-q")

	for _, c := range []struct {
		key, want, why string
	}{
		{"gc.auto", "0", "auto-gc is the background process most likely to outlive its command and race the TempDir cleanup"},
		{"gc.autoDetach", "false", "a gc that cannot detach finishes before the command returns, so it cannot race anything"},
		{"maintenance.auto", "false", "scheduled background maintenance is a second spawner"},
		{"core.fsmonitor", "false", "the fsmonitor daemon watches the working tree and is switched on by CONFIG — a runner can enable it for repos that never asked"},
		{"commit.gpgsign", "false", "a developer with signing on would otherwise see every git fixture fail on a missing key"},
		// UNLISTED keys — the ones the -c flags cannot help with, and therefore
		// the ones that prove the global cut-off is doing work. An earlier
		// version of this test asserted only listed keys and PASSED with the
		// global isolation removed: it was measuring the -c flags twice and the
		// cut-off not at all.
		{"core.autocrlf", "", "an unlisted setting must not reach a fixture — the -c flags can only override keys someone remembered"},
		{"core.hooksPath", "", "a machine's hooksPath would run its hooks inside every fixture this repo builds"},
	} {
		if got := runAllowingMiss(t, dir, "config", "--get", c.key); got != c.want {
			t.Errorf(`HOST CONFIG LEAKED IN: %s resolved to %q, want %q.

%s

The global config in this test deliberately sets the opposite. If it wins, the
harness is not its own environment: the suite behaves differently on a laptop,
on a runner, and on the next runner — which is exactly the failure this package
was written for.`, c.key, got, c.want, c.why)
		}
	}
}

// TestFixtureBranchIsDeterministic: a fixture's branch name must not depend on
// the machine. Fixtures across this repo hardcode "master", so an ambient
// init.defaultBranch is a silent way to break them somewhere else.
func TestFixtureBranchIsDeterministic(t *testing.T) {
	hostileGlobalConfig(t)
	dir := t.TempDir()

	cmd := exec.Command("git", Args("init", "-q")...)
	cmd.Dir = dir
	cmd.Env = Env()
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git init: %v\n%s", err, out)
	}

	cmd = exec.Command("git", Args("symbolic-ref", "--short", "HEAD")...)
	cmd.Dir = dir
	cmd.Env = Env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git symbolic-ref: %v\n%s", err, out)
	}
	if got := strings.TrimSpace(string(out)); got != "master" {
		t.Errorf(`a fresh fixture is on branch %q, want "master".

The hostile global config in this test asks for a different branch. Fixtures in
this repo hardcode "master"; if the machine can choose, they fail on some
machines and not others.`, got)
	}
}

// TestEveryTestGitHelperUsesThisPackage is the PATTERN guard, and it is the one
// that matters over time. Fixing the ten helpers that exist today does nothing
// for the eleventh, which someone will write by copying an older one — and the
// failure it reintroduces is a rare, non-deterministic cleanup error on a
// machine nobody is watching.
func TestEveryTestGitHelperUsesThisPackage(t *testing.T) {
	root := repoCLIRoot(t)
	var offenders []string
	scanned := 0

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || !strings.HasSuffix(path, "_test.go") {
			return nil
		}
		b, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		// This package DEFINES the rule, so it cannot bypass it — and its own
		// guidance text quotes the very call shape being searched for. Skipping
		// the definition site is narrowing the matcher to the property; adding
		// this file to an allow-list would instead have hidden a real bypass if
		// one were ever written here.
		if filepath.Dir(path) == filepath.Join(root, "internal", "testgit") {
			return nil
		}
		src := string(b)
		scanned++
		// The helper shape: a git invocation forwarding a caller's argument
		// slice. Those are the repo-building helpers; one-off read-only queries
		// (`rev-parse HEAD` and friends) spawn nothing and are not the subject.
		if strings.Contains(src, `exec.Command("git", args...)`) {
			rel, _ := filepath.Rel(root, path)
			offenders = append(offenders, rel)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if scanned == 0 {
		t.Fatal("no _test.go files were scanned — the check lost its subject, and a check that examines nothing must fail rather than pass")
	}

	if len(offenders) > 0 {
		t.Errorf(`these test git helpers bypass internal/testgit: %v

Route them through it:
    exec.Command("git", testgit.Args(args...)...)
    cmd.Env = testgit.Env()

A helper that launches git bare inherits the machine's git configuration and
leaves background maintenance enabled. That produced a real CI red — a TempDir
cleanup failing with "directory not empty" because a detached git process was
still writing — which passed on the next runner and would have been dismissed as
flaky.`, offenders)
	}
}

// runAllowingMiss reads a config key the way the helpers would, but treats "no
// such key" as the empty string rather than a failure — an absent key is
// precisely the expected result for the unlisted settings above.
func runAllowingMiss(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", Args(args...)...)
	cmd.Dir = dir
	cmd.Env = Env()
	out, _ := cmd.CombinedOutput()
	return strings.TrimSpace(string(out))
}

func repoCLIRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd() // .../cli/internal/testgit
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Dir(filepath.Dir(wd))
}
