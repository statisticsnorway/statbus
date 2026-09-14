package releasecmd

// STATBUS-366 — `release check` runs the prerelease preflight, tags nothing,
// writes nothing. prerelease is check + the tag. These tests pin the two
// properties that make `check` safe to run by anyone (including the person who
// is NOT cutting): (1) checkOnly skips every on-disk write, and (2) the check
// command shares prerelease's one preflight code path and never tags.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// stubAllWorkflowsGreen points the seam at green for every workflow. The drift
// escape's own stub (stubWorkflowCheck) asserts the workflow is FastTests; the
// full preflight consults several workflows, so this stub answers green for all
// of them without asserting a specific one.
func stubAllWorkflowsGreen(t *testing.T) {
	t.Helper()
	old := checkWorkflowAtCommit
	checkWorkflowAtCommit = func(workflow, commit string) release.WorkflowCheckResult {
		return release.WorkflowCheckResult{
			Status: release.WorkflowCheckGreen,
			RunID:  7,
			RunURL: "https://github.com/statisticsnorway/statbus/actions/runs/7",
		}
	}
	t.Cleanup(func() { checkWorkflowAtCommit = old })
}

// skipNonLocalGates sets every SKIP bypass the preflight honours so the only
// network-ish gates left are the workflow oracles (stubbed via the seam) and the
// git checks against a local fixture.
func skipNonLocalGates(t *testing.T) {
	t.Helper()
	for _, kv := range [][2]string{
		{"SKIP_IMAGES", "1"},
		{"SKIP_GO_TEST", "1"},
		{"SKIP_APP_BUILD_LINT", "1"},
		{"SKIP_SSHDOERS", "1"},
	} {
		t.Setenv(kv[0], kv[1])
	}
}

// TestCheckOnly_SkipsCIGreenStampWrite pins the CI-green branch of check 7:
// prerelease (checkOnly=false) refreshes tmp/fast-test-passed-sha and writes
// tmp/last-preflight-result; check (checkOnly=true) writes neither, and says so
// on the line that would otherwise say "writing local stamp".
func TestCheckOnly_SkipsCIGreenStampWrite(t *testing.T) {
	t.Run("check writes nothing and announces the skip", func(t *testing.T) {
		dir := newDriftRepo(t)
		stubAllWorkflowsGreen(t)
		skipNonLocalGates(t)

		out := captureStdout(t, func() {
			_ = preflightChecks(dir, true)
		})

		if _, err := os.Stat(fastTestStampPath(dir)); err == nil {
			t.Fatal("check wrote tmp/fast-test-passed-sha — check must leave no file under tmp/")
		} else if !os.IsNotExist(err) {
			t.Fatalf("stating the stamp: %v", err)
		}
		if _, err := os.Stat(filepath.Join(dir, "tmp", "last-preflight-result")); err == nil {
			t.Fatal("check wrote tmp/last-preflight-result — check must leave no file under tmp/")
		} else if !os.IsNotExist(err) {
			t.Fatalf("stating last-preflight-result: %v", err)
		}
		if !strings.Contains(out, "(not written: release check)") {
			t.Fatalf("check did not say the stamp write was skipped; output:\n%s", out)
		}
		if strings.Contains(out, "writing local stamp") {
			t.Fatalf("check printed the prerelease stamp-write line; output:\n%s", out)
		}
	})

	t.Run("prerelease still writes the stamp", func(t *testing.T) {
		dir := newDriftRepo(t)
		stubAllWorkflowsGreen(t)
		skipNonLocalGates(t)

		_ = preflightChecks(dir, false)

		if _, err := os.Stat(fastTestStampPath(dir)); err != nil {
			t.Fatalf("prerelease did not refresh the CI-green stamp: %v", err)
		}
		if _, err := os.Stat(filepath.Join(dir, "tmp", "last-preflight-result")); err != nil {
			t.Fatalf("prerelease did not write last-preflight-result: %v", err)
		}
	})
}

// TestCheckOnly_DriftEscapeSkipsStampWrite pins the other stamp-write site: the
// drift escape. It is a gate RELAXATION that refreshes the local stamp on the
// escape path — but only for prerelease; check must leave no file behind.
func TestCheckOnly_DriftEscapeSkipsStampWrite(t *testing.T) {
	dir := newDriftRepo(t)
	stubWorkflowCheck(t, release.WorkflowCheckGreen)

	var out string
	covered, _ := captureDriftVerdict(t, dir, true, &out)
	if !covered {
		t.Fatalf("the escape must still pass under check; output:\n%s", out)
	}
	if _, err := os.Stat(fastTestStampPath(dir)); err == nil {
		t.Fatal("check wrote a stamp on the drift-escape path")
	} else if !os.IsNotExist(err) {
		t.Fatalf("stating the stamp: %v", err)
	}
	if !strings.Contains(out, "Local stamp not written (release check)") {
		t.Fatalf("check did not announce the skipped drift-escape write; output:\n%s", out)
	}
}

// captureDriftVerdict runs the drift escape and captures its stdout into *out,
// so the "not written" announcement can be asserted alongside the verdict.
func captureDriftVerdict(t *testing.T, dir string, checkOnly bool, out *string) (bool, release.WorkflowCheckResult) {
	t.Helper()
	var covered bool
	var ciResult release.WorkflowCheckResult
	*out = captureStdout(t, func() {
		covered, ciResult = driftCoveredByCIGreen(dir, "latest migrations", "migrations/20260101000000_seed.up.sql", false, checkOnly)
	})
	return covered, ciResult
}

// TestCheckCommand_TagsNothingAndSharesPreflight pins, at the source, the two
// structural properties a behavioural run of the full green tree is too heavy
// to exercise offline (signed HEAD, origin, a buildable cli/): the check command
// runs prerelease's exact preflight with checkOnly=true, and it never tags or
// pushes. If these drift, `check` silently gains a write or a tag, which is the
// whole defect STATBUS-366 exists to prevent.
func TestCheckCommand_TagsNothingAndSharesPreflight(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release/release.go"))
	if err != nil {
		t.Fatal(err)
	}
	code := string(src)

	// The check command must run the SAME preflight as prerelease, flagged
	// checkOnly. One code path is the ticket's work item 2.
	if !strings.Contains(code, "preflightChecks(projDir, true)") {
		t.Error("release check does not call preflightChecks(projDir, true) — it must run prerelease's exact preflight with checkOnly")
	}
	if !strings.Contains(code, "preflightChecks(projDir, false)") {
		t.Error("release prerelease does not call preflightChecks(projDir, false) — check and prerelease must share one code path")
	}

	// The check command's RunE must not tag or push. Bound the scan to the check
	// command's own definition so a later `git tag` in prerelease does not false-
	// positive this pin.
	checkIdx := strings.Index(code, "var releaseCheckCmd = &cobra.Command{")
	if checkIdx < 0 {
		t.Fatal("could not locate releaseCheckCmd — re-anchor this pin")
	}
	window := code[checkIdx:]
	if end := strings.Index(window, "\nvar releasePrereleaseCmd"); end > 0 {
		window = window[:end]
	}
	for _, forbidden := range []string{
		`"git", "tag"`,
		`"git", "push"`,
		`git tag`,
		`git push`,
	} {
		if strings.Contains(window, forbidden) {
			t.Errorf("release check's RunE contains %q — check must never tag or push", forbidden)
		}
	}
}
