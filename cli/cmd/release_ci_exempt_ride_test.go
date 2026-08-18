package cmd

// STATBUS-219 Stage 1 oracles: a prerelease VERDICT gate may accept a green run
// at an ancestor whose entire difference from the tip is test-irrelevant.
//
// The whole mechanism turns on ONE inversion, so it gets the most tests: the
// exempt match must be UNDER-inclusive (anchored prefix), the mirror of
// diffTouchesSensitivePath's deliberately OVER-inclusive substring containment.
// An over-inclusive exempt match does not cost an extra CI run — it waves
// untested code into a release.
//
// The walk arms run against real git fixtures with the GitHub API supplied
// through the release.go seam vars, so every refusal path is pinned offline.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// TestFileIsCIExempt_AnchoredPrefixNotSubstring is the inversion pin. Four of
// the "must NOT be exempt" cases below are ones that substring containment —
// the rule the sensitivity list next door uses, and the wrong conservatism to
// copy here — WOULD have wrongly exempted: vendor/.backlog/thing.md, the
// git-quoted path, and both doc-vs-docker cases. Swapping this helper to
// strings.Contains turns those four red immediately (verified).
func TestFileIsCIExempt_AnchoredPrefixNotSubstring(t *testing.T) {
	exempt := []string{".backlog/"}
	for _, tc := range []struct {
		file string
		want bool
		why  string
	}{
		{".backlog/tasks/statbus-219 - x.md", true, "a real board file"},
		{".backlog/docs/doc-030.md", true, "board docs are board files"},
		{"app/src/.backlog-widget.ts", false, "app code merely carrying the name is not board content"},
		{"vendor/.backlog/thing.md", false, "SUBSTRING CONTAINMENT WOULD EXEMPT THIS — an exempt directory nested elsewhere is not the exempt directory"},
		{"cli/cmd/release.go", false, "ordinary code"},
		{".backlogger/notes.md", false, "a sibling directory sharing the prefix without the separator"},
		{"", false, "an empty path is never exempt"},
		{`"\303\251.backlog/x.md"`, false, "a git-quoted path (non-ASCII) must fall on the safe side"},
	} {
		if got := fileIsCIExempt(tc.file, exempt); got != tc.want {
			t.Errorf("fileIsCIExempt(%q) = %v, want %v — %s", tc.file, got, tc.want, tc.why)
		}
	}

	// An entry WITHOUT a trailing slash matches that file, or that directory's
	// contents — never a sibling that merely starts with the same letters.
	entry := []string{"doc"}
	for _, tc := range []struct {
		file string
		want bool
	}{
		{"doc", true},
		{"doc/readme.md", true},
		{"docker-compose.yml", false},
		{"docs/readme.md", false},
	} {
		if got := fileIsCIExempt(tc.file, entry); got != tc.want {
			t.Errorf("entry %q: fileIsCIExempt(%q) = %v, want %v", entry[0], tc.file, got, tc.want)
		}
	}
}

// TestChangedFilesAllExempt_OneOffenderForbidsTheRide: exemption is universally
// quantified. One non-exempt file anywhere in the diff forbids the ride, no
// matter how much board text accompanies it (AC#4's unit-level half).
func TestChangedFilesAllExempt_OneOffenderForbidsTheRide(t *testing.T) {
	exempt := []string{".backlog/"}

	allExempt, justifying, offenders := changedFilesAllExempt(
		[]string{".backlog/tasks/a.md", ".backlog/tasks/b.md"}, exempt)
	if !allExempt || len(justifying) != 2 || len(offenders) != 0 {
		t.Errorf("all-board diff: got allExempt=%v justifying=%v offenders=%v, want exempt with 2 justifying", allExempt, justifying, offenders)
	}

	allExempt, _, offenders = changedFilesAllExempt(
		[]string{".backlog/tasks/a.md", "cli/cmd/release.go", ".backlog/tasks/b.md"}, exempt)
	if allExempt {
		t.Error("a diff containing cli/cmd/release.go must NOT be exempt — one non-exempt file forbids the ride however much board text surrounds it")
	}
	if len(offenders) != 1 || offenders[0] != "cli/cmd/release.go" {
		t.Errorf("offenders = %v, want exactly [cli/cmd/release.go] so the refusal can name it", offenders)
	}

	// The empty diff: identical trees. Riding is sound by definition — this is
	// the add-then-revert case the DIRECT diff exists to make visible.
	allExempt, justifying, _ = changedFilesAllExempt(nil, exempt)
	if !allExempt || len(justifying) != 0 {
		t.Errorf("an empty diff means identical trees and must ride: got allExempt=%v justifying=%v", allExempt, justifying)
	}
}

// TestCIExemptPathsFile_IsNotItselfExempt is AC#5, enforced mechanically rather
// than remembered: changing what counts as test-irrelevant can never ride a
// prior green. If someone adds `ops/` — or the file's own path — to the list,
// this fails.
func TestCIExemptPathsFile_IsNotItselfExempt(t *testing.T) {
	exempt, err := loadCIExemptPaths(thisRepoFile(t, "."))
	if err != nil {
		t.Fatalf("loadCIExemptPaths: %v", err)
	}
	if len(exempt) == 0 {
		t.Fatal("the exempt list is empty — if that is deliberate, the ride mechanism is dead code")
	}
	if fileIsCIExempt(ciExemptPathsFile, exempt) {
		t.Fatalf("%s matches its OWN list (%v) — changing what counts as test-irrelevant would then ride a prior green, which is exactly the act that must always be tested (AC#5)", ciExemptPathsFile, exempt)
	}
	// The sibling sensitivity list must not be exempt either: narrowing the
	// upgrade gate is not a test-irrelevant edit.
	if fileIsCIExempt(upgradeSensitivePathsFile, exempt) {
		t.Errorf("%s must never be exempt — editing the upgrade-sensitivity list is a gated act", upgradeSensitivePathsFile)
	}
	// Neither may the workflows or the release code that implement the gates.
	for _, mustNot := range []string{
		"cli/cmd/release.go",
		".github/workflows/pg_regress.yaml",
		"migrations/20260101000000_x.up.sql",
		"app/src/app/page.tsx",
		"test/expected/foo.out",
	} {
		if fileIsCIExempt(mustNot, exempt) {
			t.Errorf("%s must never be exempt", mustNot)
		}
	}
}

// rideFixture builds a repo whose tip is `boardCommits` board-only commits past
// a code commit, and returns (dir, tipSHA, codeSHA).
func rideFixture(t *testing.T, boardCommits int) (string, string, string) {
	t.Helper()
	dir := t.TempDir()
	runGitInCmd(t, dir, "init", "-q")
	writeAndCommit(t, dir, "code", "cli/cmd/release.go", "migrations/20260101000000_init.up.sql")

	// The exempt list must exist in the fixture — the ride reads it from the tree.
	exemptSrc, err := os.ReadFile(thisRepoFile(t, ciExemptPathsFile))
	if err != nil {
		t.Fatal(err)
	}
	full := filepath.Join(dir, ciExemptPathsFile)
	if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, exemptSrc, 0644); err != nil {
		t.Fatal(err)
	}
	runGitInCmd(t, dir, "add", ".")
	runGitInCmd(t, dir, "commit", "-q", "-m", "exempt list")
	codeSHA := runGitInCmd(t, dir, "rev-parse", "HEAD")

	for i := 0; i < boardCommits; i++ {
		writeAndCommit(t, dir, "board", filepath.Join(".backlog", "tasks", "t"+string(rune('a'+i))+".md"))
	}
	return dir, runGitInCmd(t, dir, "rev-parse", "HEAD"), codeSHA
}

// greenAt returns a seam stub that reports green for exactly one commit.
func greenAt(commit string) func(string, string) release.WorkflowCheckResult {
	return func(workflow, sha string) release.WorkflowCheckResult {
		if sha == commit {
			return release.WorkflowCheckResult{
				Status: release.WorkflowCheckGreen,
				RunID:  7,
				RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/7",
			}
		}
		return release.WorkflowCheckResult{Status: release.WorkflowCheckPending, RunID: 8}
	}
}

// TestFindExemptRide_BoardOnlyCommitsRideTheAncestor is AC#3: the tip is three
// board commits past the last tested code commit, so the gate rides it.
func TestFindExemptRide_BoardOnlyCommitsRideTheAncestor(t *testing.T) {
	dir, tip, code := rideFixture(t, 3)
	stubWorkflowSeams(t, greenAt(code), trivialComplete)

	ride, whyNot := findExemptRide(dir, release.WorkflowFastTests, tip)
	if ride == nil {
		t.Fatalf("expected a ride onto the last code commit; refused with: %s", whyNot)
	}
	if ride.Commit != code {
		t.Errorf("ride target = %s, want the last tested code commit %s", ride.Commit, code)
	}
	if ride.CommitsRidden != 3 {
		t.Errorf("CommitsRidden = %d, want 3 — the operator must see how far the tip has moved", ride.CommitsRidden)
	}
	if len(ride.Justifying) != 3 {
		t.Errorf("Justifying = %v, want the 3 board files that justified the ride", ride.Justifying)
	}
	for _, f := range ride.Justifying {
		if !strings.HasPrefix(f, ".backlog/") {
			t.Errorf("justifying file %q is not exempt — the ride must only ever be justified by exempt paths", f)
		}
	}
}

// TestFindExemptRide_EmDashedBoardFilenamesStillRide is the regression arm for
// the -z amendment, and it is the case the original fixtures could not catch:
// every board file they created was plain ASCII.
//
// `git diff --name-only` QUOTES any path containing non-ASCII bytes, and this
// repo's real board filenames carry em-dashes — so without -z the ride would be
// INERT on exactly the commits it exists to unblock: the quoted paths fail the
// anchored-prefix match, get classed non-exempt, and the gate refuses. Verified
// against real history before the fix: 2 of 3 paths came back quoted.
//
// Reverting findExemptRide to the newline split turns this red while every
// other ride test stays green — which is precisely how the defect hid.
func TestFindExemptRide_EmDashedBoardFilenamesStillRide(t *testing.T) {
	dir, _, code := rideFixture(t, 0)

	// A filename in the repo's real board style: em-dash, spaces, ticket prefix.
	writeAndCommit(t, dir, "board",
		filepath.Join(".backlog", "tasks", "statbus-219 - board-push-ci-decouple — a two-line ticket edit stalls a cut.md"))
	writeAndCommit(t, dir, "board",
		filepath.Join(".backlog", "docs", "doc-030 - design ruling — STATBUS-219.md"))
	tip := runGitInCmd(t, dir, "rev-parse", "HEAD")

	stubWorkflowSeams(t, greenAt(code), trivialComplete)

	ride, whyNot := findExemptRide(dir, release.WorkflowFastTests, tip)
	if ride == nil {
		t.Fatalf("board commits with em-dashed filenames must ride — they are the whole point of the mechanism. Refused with: %s\n"+
			"(if this is the only failing ride test, the diff is being read WITHOUT -z and git is quoting the paths)", whyNot)
	}
	if ride.Commit != code {
		t.Errorf("ride target = %s, want %s", ride.Commit, code)
	}
	for _, f := range ride.Justifying {
		if !strings.HasPrefix(f, ".backlog/") {
			t.Errorf("justifying path %q did not arrive raw — a quoted or mangled path must never count as exempt", f)
		}
		if strings.HasPrefix(f, `"`) {
			t.Errorf("path %q arrived QUOTED — the diff must be read with -z", f)
		}
	}
	if len(ride.Justifying) != 2 {
		t.Errorf("Justifying = %v, want both board files", ride.Justifying)
	}
}

// TestFindExemptRide_NonExemptChangeRefuses is AC#4: a code change anywhere in
// the diff means this code state has not been tested, and no amount of board
// text around it may wave it through.
func TestFindExemptRide_NonExemptChangeRefuses(t *testing.T) {
	dir, _, code := rideFixture(t, 2)
	// A real code change lands on top of the board commits.
	writeAndCommit(t, dir, "code change", "cli/internal/upgrade/service.go")
	writeAndCommit(t, dir, "more board", ".backlog/tasks/zz.md")
	tip := runGitInCmd(t, dir, "rev-parse", "HEAD")

	stubWorkflowSeams(t, greenAt(code), trivialComplete)

	ride, whyNot := findExemptRide(dir, release.WorkflowFastTests, tip)
	if ride != nil {
		t.Fatalf("RODE a tip containing a non-exempt change (target %s) — untested code would enter a release", ride.Commit)
	}
	if !strings.Contains(whyNot, "service.go") {
		t.Errorf("the refusal must name the offending file so the operator knows this code state is untested: got %q", whyNot)
	}
	if !strings.Contains(whyNot, "not been tested") {
		t.Errorf("the refusal must say plainly that the code state is untested (waiting will not fix it): got %q", whyNot)
	}
}

// TestFindExemptRide_AddThenRevertRidesTheOlderAncestor pins the reason the
// walk computes a DIRECT diff and does NOT stop at the first non-exempt
// candidate: a commit that adds code and a later one that reverts it leave an
// OLDER ancestor tree-identical to the tip. Stopping early would discard a
// sound ride; per-hop induction would never see it at all.
func TestFindExemptRide_AddThenRevertRidesTheOlderAncestor(t *testing.T) {
	dir, _, code := rideFixture(t, 1)

	// Add a code file, then delete it again — the tree returns to `code`'s state
	// apart from board text.
	scratch := filepath.Join(dir, "cli", "internal", "scratch.go")
	if err := os.MkdirAll(filepath.Dir(scratch), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(scratch, []byte("package internal\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runGitInCmd(t, dir, "add", ".")
	runGitInCmd(t, dir, "commit", "-q", "-m", "add scratch")
	if err := os.Remove(scratch); err != nil {
		t.Fatal(err)
	}
	runGitInCmd(t, dir, "add", "-A")
	runGitInCmd(t, dir, "commit", "-q", "-m", "revert scratch")
	tip := runGitInCmd(t, dir, "rev-parse", "HEAD")

	stubWorkflowSeams(t, greenAt(code), trivialComplete)

	ride, whyNot := findExemptRide(dir, release.WorkflowFastTests, tip)
	if ride == nil {
		t.Fatalf("an add-then-revert pair leaves the trees identical apart from board text — that ride is sound and must be found; refused with: %s", whyNot)
	}
	if ride.Commit != code {
		t.Errorf("ride target = %s, want %s", ride.Commit, code)
	}
}

// TestFindExemptRide_NoGreenAncestorRefuses: the diff is exempt-clean, but no
// ancestor has a green run either. Nothing to ride — refuse, saying so.
func TestFindExemptRide_NoGreenAncestorRefuses(t *testing.T) {
	dir, tip, _ := rideFixture(t, 2)
	stubWorkflowSeams(t,
		func(workflow, sha string) release.WorkflowCheckResult {
			return release.WorkflowCheckResult{Status: release.WorkflowCheckPending, RunID: 9}
		}, trivialComplete)

	ride, whyNot := findExemptRide(dir, release.WorkflowFastTests, tip)
	if ride != nil {
		t.Fatalf("rode %s though no ancestor was green", ride.Commit)
	}
	if !strings.Contains(whyNot, "green") {
		t.Errorf("the refusal must say the exempt-clean ancestors had no green run: got %q", whyNot)
	}
}

// TestFindExemptRide_MissingExemptListRefuses: no list, no ride. A deleted or
// unreadable list must fail CLOSED (refuse), never open.
func TestFindExemptRide_MissingExemptListRefuses(t *testing.T) {
	dir, _, code := rideFixture(t, 2)
	if err := os.Remove(filepath.Join(dir, ciExemptPathsFile)); err != nil {
		t.Fatal(err)
	}
	runGitInCmd(t, dir, "add", "-A")
	runGitInCmd(t, dir, "commit", "-q", "-m", "remove exempt list")
	tip := runGitInCmd(t, dir, "rev-parse", "HEAD")

	stubWorkflowSeams(t, greenAt(code), trivialComplete)

	ride, whyNot := findExemptRide(dir, release.WorkflowFastTests, tip)
	if ride != nil {
		t.Fatal("a missing exempt list must refuse the ride (fail closed), not ride everything")
	}
	if !strings.Contains(whyNot, ciExemptPathsFile) {
		t.Errorf("the refusal must name the unreadable list: got %q", whyNot)
	}
}

// TestFindExemptRide_WalkIsBounded: the walk stops at ciExemptRideWalkBound
// ancestors rather than marching down the whole history issuing an API call per
// exempt-clean candidate.
func TestFindExemptRide_WalkIsBounded(t *testing.T) {
	dir, _, _ := rideFixture(t, 0)
	for i := 0; i < ciExemptRideWalkBound+5; i++ {
		writeAndCommit(t, dir, "board", filepath.Join(".backlog", "tasks", fmt.Sprintf("b%d.md", i)))
	}
	tip := runGitInCmd(t, dir, "rev-parse", "HEAD")

	probed := 0
	stubWorkflowSeams(t,
		func(workflow, sha string) release.WorkflowCheckResult {
			probed++
			return release.WorkflowCheckResult{Status: release.WorkflowCheckMissing}
		}, trivialComplete)

	ride, _ := findExemptRide(dir, release.WorkflowFastTests, tip)
	if ride != nil {
		t.Fatal("no ancestor was green — expected no ride")
	}
	if probed > ciExemptRideWalkBound {
		t.Errorf("probed %d ancestors, bound is %d — an unbounded walk would issue an API call per commit of history", probed, ciExemptRideWalkBound)
	}
}

// TestPrereleaseGate_RidesAndRefusesLoudly drives the real gate function end to
// end: it must accept the ride, print the tested commit and every justifying
// file, and — when the ride does not apply — keep today's refusal AND say why
// the ride was unavailable. Silence in either direction is the failure mode.
func TestPrereleaseGate_RidesAndRefusesLoudly(t *testing.T) {
	t.Run("rides: board-only diff, ancestor green", func(t *testing.T) {
		dir, _, code := rideFixture(t, 2)
		stubWorkflowSeams(t, greenAt(code), trivialComplete)

		var passed bool
		out := captureStdout(t, func() {
			passed = checkPrereleaseWorkflowGate(dir, release.WorkflowFastTests, "fast-tests", "SKIP_FAST_TESTS")
		})
		if !passed {
			t.Fatalf("the gate refused a tip whose only diff is board text, with the ancestor green; output:\n%s", out)
		}
		if !strings.Contains(out, "also covers this commit") || !strings.Contains(out, code) {
			t.Errorf("the ride must be LOUD — naming the tested commit; output:\n%s", out)
		}
		if !strings.Contains(out, ".backlog/") {
			t.Errorf("the ride must print every file that justified it; output:\n%s", out)
		}
	})

	t.Run("refuses: non-exempt change in the diff", func(t *testing.T) {
		dir, _, code := rideFixture(t, 1)
		writeAndCommit(t, dir, "code change", "cli/internal/upgrade/service.go")
		stubWorkflowSeams(t, greenAt(code), trivialComplete)

		var passed bool
		out := captureStdout(t, func() {
			passed = checkPrereleaseWorkflowGate(dir, release.WorkflowFastTests, "fast-tests", "SKIP_FAST_TESTS")
		})
		if passed {
			t.Fatalf("the gate PASSED a tip carrying an untested code change; output:\n%s", out)
		}
		if !strings.Contains(out, "No earlier green run also covers this commit") {
			t.Errorf("the refusal must say the ride was considered and why it did not apply; output:\n%s", out)
		}
		if !strings.Contains(out, "service.go") {
			t.Errorf("the refusal must name the offending file; output:\n%s", out)
		}
	})

	t.Run("never rides on Unknown: an unreachable API cannot verify an ancestor", func(t *testing.T) {
		dir, _, _ := rideFixture(t, 2)
		probed := 0
		stubWorkflowSeams(t,
			func(workflow, sha string) release.WorkflowCheckResult {
				probed++
				return release.WorkflowCheckResult{Status: release.WorkflowCheckUnknown, Detail: "dial tcp: no route to host"}
			}, trivialComplete)

		var passed bool
		out := captureStdout(t, func() {
			passed = checkPrereleaseWorkflowGate(dir, release.WorkflowFastTests, "fast-tests", "SKIP_FAST_TESTS")
		})
		if passed {
			t.Fatalf("an API error must refuse; output:\n%s", out)
		}
		if probed != 1 {
			t.Errorf("probed %d times — on Unknown the walk must not run at all (the same API is what would verify the ancestor)", probed)
		}
		if strings.Contains(out, "No earlier green run also covers this commit") {
			t.Errorf("on Unknown the ride is not attempted, so it must not be reported as unavailable; output:\n%s", out)
		}
	})
}

// TestImagesGateNeverRides is the permanence pin for doc-030's Finding 1: the
// images check must never gain a ride. images asks whether artifacts EXIST at
// the SHA — a question about the world, not the code — so a content argument
// can never satisfy it.
func TestImagesGateNeverRides(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release.go"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(src)

	imagesIdx := strings.Index(text, "imagesResult := release.CheckWorkflowAtCommit(release.WorkflowImages")
	if imagesIdx < 0 {
		t.Fatal("could not locate the images gate — re-anchor this pin rather than letting it stop checking")
	}
	// The images switch runs to the end of preflightChecks' image handling; scan
	// a generous window after it for any ride call.
	window := text[imagesIdx:]
	if end := strings.Index(window, "\nfunc "); end > 0 {
		window = window[:end]
	}
	if strings.Contains(window, "findExemptRide(") {
		t.Error("the images gate calls findExemptRide — images can NEVER ride an ancestor: it asks whether Docker artifacts EXIST at this SHA, and no content argument makes an image materialise where nothing published. A release cut on such a commit is undeployable (doc-030 Finding 1)")
	}
	if !strings.Contains(text, "IMAGES NEVER RIDES") {
		t.Error("the images gate must carry the never-rides reason in code, so the exclusion survives someone unifying the gates later")
	}
}
