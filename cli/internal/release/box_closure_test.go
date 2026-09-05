package release

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string { return repoRootForRelease(t) }

func has(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}

// At HEAD the boundary exists. The closure must contain the packages ordinary
// cmd reaches and must NOT contain the release engine.
func TestBoxCommandClosure_AtHEADExcludesReleaseEngine_STATBUS352(t *testing.T) {
	c, err := BoxCommandClosureAt(repoRoot(t), "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if c.Broad {
		t.Fatal("HEAD has the boundary marker; closure must be derived, not broad")
	}
	for _, want := range []string{"cli/cmd", "cli/internal/upgrade", "cli/internal/migrate", "cli/internal/config"} {
		if !has(c.Dirs, want) {
			t.Errorf("closure at HEAD lacks %s: %v", want, c.Dirs)
		}
	}
	for _, forbidden := range []string{"cli/cmd/release", "cli/internal/release"} {
		if has(c.Dirs, forbidden) {
			t.Errorf("closure at HEAD contains release engine dir %s", forbidden)
		}
	}
	for _, f := range []string{"cli/main.go", "cli/go.mod", "cli/go.sum"} {
		if !has(c.Files, f) {
			t.Errorf("build input %s missing from closure files", f)
		}
	}
	// Memoized: a second call is the same value and does not re-derive.
	again, err := BoxCommandClosureAt(repoRoot(t), c.Commit)
	if err != nil || strings.Join(again.Dirs, ",") != strings.Join(c.Dirs, ",") {
		t.Fatalf("cache miss or drift: %v / %v", err, again.Dirs)
	}
}

// A commit BEFORE the extraction has no boundary: the whole cli/ tree stays
// box payload, exactly as before the optimizer existed.
func TestBoxCommandClosure_PreBoundaryCommitIsBroad_STATBUS352(t *testing.T) {
	// db89f876c is the last commit before C1 landed (262933346).
	c, err := BoxCommandClosureAt(repoRoot(t), "db89f876c")
	if err != nil {
		t.Fatal(err)
	}
	if !c.Broad {
		t.Fatalf("pre-boundary commit must be broad; got dirs %v", c.Dirs)
	}
	rules, err := boxPayloadRulesForRange(repoRoot(t), "db89f876c", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if len(rules) != 1 || rules[0].Path != "cli" || rules[0].Kind != matchDirectory {
		t.Fatalf("a range with a broad end must yield the single broad cli rule; got %v", rules)
	}
}

// End to end through DiffSensitiveChanges at HEAD..HEAD-with-release-only-edit
// would need a commit; instead prove the rule substitution: with the boundary
// on both ends, a release-engine path is proof interpreter and an ordinary
// cmd path is box payload, while a path in NEITHER closure nor policy is not
// sensitive at all.
func TestNarrowCLIPayloadRules_SubstitutesClosureForBroadRule_STATBUS352(t *testing.T) {
	root := repoRoot(t)
	broad, err := loadSensitivityPolicy(root)
	if err != nil {
		t.Fatal(err)
	}
	narrowed, err := narrowCLIPayloadRules(root, "HEAD", "HEAD", broad)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range narrowed {
		if r.Kind == matchDirectory && r.Path == "cli" {
			t.Fatal("broad cli rule survived narrowing")
		}
	}
	scenario := Scenario{Name: "a", Home: WorkflowFleet}
	cases := []struct {
		path   string
		match  bool
		reason SensitivityReason
	}{
		{"cli/internal/upgrade/service.go", true, ReasonBoxPayload},
		{"cli/cmd/install.go", true, ReasonBoxPayload},
		{"cli/main.go", true, ReasonBoxPayload},
		{"cli/go.sum", true, ReasonBoxPayload},
		{"cli/cmd/release/release.go", true, ReasonProofInterpreter},
		{"cli/internal/release/coverage.go", true, ReasonProofInterpreter},
		{"cli/README.md", false, ""},
		{"cli/src/manage.cr", false, ""}, // retired Crystal source, not in the Go closure
	}
	for _, tc := range cases {
		change, matched, err := matchSensitivePathWithRules(narrowed, scenario, tc.path)
		if err != nil {
			t.Fatal(err)
		}
		if matched != tc.match || change.Reason != tc.reason {
			t.Errorf("%s: matched=%v reason=%q, want %v %q", tc.path, matched, change.Reason, tc.match, tc.reason)
		}
	}
}

// Undecidable: a commit whose cli/ module cannot be listed (go.mod names a
// module that is not in the module cache, GOPROXY=off) is an ERROR, never a
// narrowed closure and never broad-by-accident.
func TestBoxCommandClosure_UnlistableModuleIsUndecidable_STATBUS352(t *testing.T) {
	dir := t.TempDir()
	gitFixture(t, dir, "init", "-q")
	writeFile(t, dir, "cli/go.mod", "module example.invalid/broken\n\ngo 1.25\n\nrequire example.invalid/nonexistent v0.0.1\n", 0o644)
	writeFile(t, dir, "cli/main.go", "package main\n\nfunc main() {}\n", 0o644)
	writeFile(t, dir, "cli/cmd/cmd.go", "package cmd\n\nimport _ \"example.invalid/nonexistent\"\n", 0o644)
	writeFile(t, dir, "cli/cmd/release/command.go", "package releasecmd\n", 0o644)
	gitFixture(t, dir, "add", ".")
	gitFixture(t, dir, "commit", "-q", "-m", "broken module")
	head := gitFixture(t, dir, "rev-parse", "HEAD")

	c, err := BoxCommandClosureAt(dir, head)
	if err == nil {
		t.Fatalf("an unlistable module must be undecidable; got %+v", c)
	}
	if _, err := boxPayloadRulesForRange(dir, head, head); err == nil {
		t.Fatal("range over an undecidable commit must error, never narrow")
	}
	if out := gitFixture(t, dir, "status", "--porcelain"); out != "" {
		t.Fatalf("derivation mutated the working tree:\n%s", out)
	}
}

// Union: a package present at the anchor but deleted at the target must still
// be sensitive (its deletion IS a box change).
func TestBoxPayloadRulesForRange_UnionKeepsDeletedDependency_STATBUS352(t *testing.T) {
	dir := t.TempDir()
	gitFixture(t, dir, "init", "-q")
	writeFile(t, dir, "cli/go.mod", "module example.test/cli\n\ngo 1.25\n", 0o644)
	writeFile(t, dir, "cli/main.go", "package main\n\nimport _ \"example.test/cli/cmd\"\n\nfunc main() {}\n", 0o644)
	writeFile(t, dir, "cli/cmd/cmd.go", "package cmd\n\nimport _ \"example.test/cli/internal/old\"\n", 0o644)
	writeFile(t, dir, "cli/internal/old/old.go", "package old\n", 0o644)
	writeFile(t, dir, "cli/cmd/release/command.go", "package releasecmd\n", 0o644)
	gitFixture(t, dir, "add", ".")
	gitFixture(t, dir, "commit", "-q", "-m", "anchor")
	anchor := gitFixture(t, dir, "rev-parse", "HEAD")

	writeFile(t, dir, "cli/cmd/cmd.go", "package cmd\n\nimport _ \"example.test/cli/internal/new\"\n", 0o644)
	writeFile(t, dir, "cli/internal/new/new.go", "package new\n", 0o644)
	if err := os.RemoveAll(filepath.Join(dir, "cli/internal/old")); err != nil {
		t.Fatal(err)
	}
	gitFixture(t, dir, "add", "-A")
	gitFixture(t, dir, "commit", "-q", "-m", "target")
	target := gitFixture(t, dir, "rev-parse", "HEAD")

	rules, err := boxPayloadRulesForRange(dir, anchor, target)
	if err != nil {
		t.Fatal(err)
	}
	var paths []string
	for _, r := range rules {
		paths = append(paths, r.Path)
	}
	for _, want := range []string{"cli/cmd", "cli/internal/old", "cli/internal/new", "cli/main.go"} {
		if !has(paths, want) {
			t.Errorf("union lacks %s: %v", want, paths)
		}
	}
	if has(paths, "cli/cmd/release") {
		t.Errorf("release package must not be in the box closure: %v", paths)
	}
}
