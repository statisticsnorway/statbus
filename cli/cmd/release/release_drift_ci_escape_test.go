package releasecmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// The drift-refusal escape is a gate RELAXATION, so its tests have to pin the
// direction it still keeps as hard as the direction it opens. Three
// properties, in the order they matter:
//
//  1. it fires ONLY on green — every other CI status still refuses
//  2. it refreshes the local stamp on the escape path
//  3. it does NOT write a stamp on the ride path, where the stamp is an
//     inference rather than evidence
//
// The GitHub read is supplied through the checkWorkflowAtCommit seam, so
// these assert the FUNCTION'S VERDICT rather than what the live API happens
// to answer. Without the seam every call returns Unknown with no network and
// the refusal tests would pass for the wrong reason — pinning nothing.

// newDriftRepo builds a real git repo with one commit, because the escape
// resolves HEAD itself and a fixture that cannot answer `git rev-parse HEAD`
// would exercise only the empty-HEAD guard.
func newDriftRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()

	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(), testgit.Env()...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	run("init")
	if err := os.WriteFile(filepath.Join(dir, "seed.txt"), []byte("x\n"), 0644); err != nil {
		t.Fatal(err)
	}
	run("add", ".")
	run("commit", "-m", "seed")

	// A migration on disk so the refreshed stamp's line 2 is a real version
	// rather than the empty string, which would hide a regression that wrote
	// the wrong field there.
	migDir := filepath.Join(dir, "migrations")
	if err := os.MkdirAll(migDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(migDir, "20260101000000_seed.up.sql"), []byte("SELECT 1;\n"), 0644); err != nil {
		t.Fatal(err)
	}
	return dir
}

// stubWorkflowCheck points the seam at a fixed answer for one test.
func stubWorkflowCheck(t *testing.T, status release.WorkflowCheckStatus) {
	t.Helper()
	old := checkWorkflowAtCommit
	checkWorkflowAtCommit = func(workflow, commit string) release.WorkflowCheckResult {
		if workflow != release.WorkflowPgRegress {
			t.Errorf("escape consulted the wrong workflow: got %q, want %q", workflow, release.WorkflowPgRegress)
		}
		if commit == "" {
			t.Error("escape consulted CI with an empty commit — it must ask about a real HEAD")
		}
		return release.WorkflowCheckResult{Status: status, RunURL: "https://example.invalid/run/1", RunID: 1}
	}
	t.Cleanup(func() { checkWorkflowAtCommit = old })
}

// TestDriftEscapeFiresOnlyOnGreen is the load-bearing one: it pins BOTH
// directions in a single table, so a change that opens the escape wider
// cannot pass by only satisfying the green case.
func TestDriftEscapeFiresOnlyOnGreen(t *testing.T) {
	cases := []struct {
		status release.WorkflowCheckStatus
		want   bool
	}{
		{release.WorkflowCheckGreen, true},
		{release.WorkflowCheckFailed, false},
		{release.WorkflowCheckPending, false},
		{release.WorkflowCheckMissing, false},
		{release.WorkflowCheckUnknown, false},
	}
	for _, tc := range cases {
		t.Run(string(tc.status), func(t *testing.T) {
			dir := newDriftRepo(t)
			stubWorkflowCheck(t, tc.status)

			got, ciResult := driftCoveredByCIGreen(dir, "test expected file drift", "test/expected/a.out", false)
			if got != tc.want {
				t.Fatalf("pg_regress %s: escape returned %v, want %v", tc.status, got, tc.want)
			}
			// STATBUS-277: the caller prints ciResult on refusal, so the
			// escape must hand back the actual status it saw rather than a
			// zero value — a refusal with an empty Status would read as
			// "CI was never consulted" when it plainly was.
			if ciResult.Status != tc.status {
				t.Fatalf("pg_regress %s: returned result status = %q, want %q", tc.status, ciResult.Status, tc.status)
			}

			// A refusal must also leave no stamp behind: writing one would
			// convert "CI is red" into a local record that the suite passed.
			_, err := os.Stat(fastTestStampPath(dir))
			stampExists := err == nil
			if stampExists != tc.want {
				t.Fatalf("pg_regress %s: stamp exists = %v, want %v", tc.status, stampExists, tc.want)
			}
		})
	}
}

// TestDriftEscapeRefreshesStampOnEscapePath pins the content, not just the
// presence: line 1 must be HEAD (so the next run's drift diff is empty) and
// line 2 the on-disk migration version (the H1 field the stale-template check
// reads).
func TestDriftEscapeRefreshesStampOnEscapePath(t *testing.T) {
	dir := newDriftRepo(t)
	stubWorkflowCheck(t, release.WorkflowCheckGreen)

	covered, _ := driftCoveredByCIGreen(dir, "latest migrations", "migrations/20260101000000_seed.up.sql", false)
	if !covered {
		t.Fatal("escape did not fire on green")
	}

	got, err := os.ReadFile(fastTestStampPath(dir))
	if err != nil {
		t.Fatalf("escape path did not refresh the stamp: %v", err)
	}
	headOut, err := exec.Command("git", "-C", dir, "rev-parse", "HEAD").Output()
	if err != nil {
		t.Fatal(err)
	}
	want := string(headOut[:len(headOut)-1]) + "\n20260101000000\n"
	if string(got) != want {
		t.Fatalf("stamp content:\n got %q\nwant %q", got, want)
	}
}

// TestDriftEscapeNeverWritesStampOnRidePath is the property the ride case
// exists to protect: a stamp synthesized from an exempt-ancestor ride is an
// INFERENCE. Persisting it would outlive the ancestor green that justified
// it, and a later reader could not tell it from evidence.
func TestDriftEscapeNeverWritesStampOnRidePath(t *testing.T) {
	dir := newDriftRepo(t)
	stubWorkflowCheck(t, release.WorkflowCheckGreen)

	covered, _ := driftCoveredByCIGreen(dir, "latest migrations", "migrations/20260101000000_seed.up.sql", true)
	if !covered {
		t.Fatal("escape must still pass on green when the stamp came from a ride")
	}

	if _, err := os.Stat(fastTestStampPath(dir)); err == nil {
		t.Fatal("ride path wrote a local stamp — an inference must never become on-disk evidence")
	} else if !os.IsNotExist(err) {
		t.Fatalf("unexpected error stating the stamp: %v", err)
	}
}

// TestDriftEscapeRefusesWithoutAHead is the zero-scope arm: a check that
// examines nothing must refuse rather than pass. A non-repo directory has no
// HEAD to ask CI about.
func TestDriftEscapeRefusesWithoutAHead(t *testing.T) {
	dir := t.TempDir()
	old := checkWorkflowAtCommit
	checkWorkflowAtCommit = func(workflow, commit string) release.WorkflowCheckResult {
		t.Error("escape consulted CI with no HEAD resolved — it must refuse before asking")
		return release.WorkflowCheckResult{Status: release.WorkflowCheckGreen}
	}
	t.Cleanup(func() { checkWorkflowAtCommit = old })

	covered, ciResult := driftCoveredByCIGreen(dir, "latest migrations", "migrations/x.up.sql", false)
	if covered {
		t.Fatal("escape passed with no HEAD — a check that examines nothing must refuse")
	}
	// STATBUS-277: printDriftEitherOrRefusal tells "declined" from "never
	// consulted" apart by Status being the zero value — pin that here too,
	// not just the boolean, or a regression that fills in a fake status
	// would slip through as a message-text nuance nobody in this test caught.
	if ciResult.Status != "" {
		t.Fatalf("no-HEAD case returned non-empty status %q — CI was never consulted", ciResult.Status)
	}
}

// TestPrintDriftEitherOrRefusal pins the STATBUS-277 message: a refusal must
// name BOTH halves of the gate — the local stamp being stale AND what CI
// actually showed — and state the disjunction, so an operator staring at
// "not covered" does not read the local run as the only accepted proof.
func TestPrintDriftEitherOrRefusal(t *testing.T) {
	t.Run("pending, with run URL", func(t *testing.T) {
		out := captureStdout(t, func() {
			printDriftEitherOrRefusal(release.WorkflowCheckResult{
				Status: release.WorkflowCheckPending,
				RunURL: "https://example.invalid/run/9",
			})
		})
		for _, want := range []string{
			"pg_regress is not green at HEAD",
			"status: pending",
			"run: https://example.invalid/run/9",
			"either a green CI run at this commit or the local run below satisfies this check",
		} {
			if !strings.Contains(out, want) {
				t.Fatalf("refusal message missing %q; got:\n%s", want, out)
			}
		}
	})

	t.Run("unknown, with API-error detail and no run URL", func(t *testing.T) {
		out := captureStdout(t, func() {
			printDriftEitherOrRefusal(release.WorkflowCheckResult{
				Status: release.WorkflowCheckUnknown,
				Detail: "GitHub API returned HTTP 403",
			})
		})
		if !strings.Contains(out, "status: unknown") || !strings.Contains(out, "detail: GitHub API returned HTTP 403") {
			t.Fatalf("refusal message missing status/detail; got:\n%s", out)
		}
		if strings.Contains(out, "run:") {
			t.Fatalf("refusal message printed a run: fragment with no RunURL; got:\n%s", out)
		}
	})

	t.Run("no HEAD — CI never consulted, must not fabricate a status", func(t *testing.T) {
		out := captureStdout(t, func() {
			printDriftEitherOrRefusal(release.WorkflowCheckResult{})
		})
		if !strings.Contains(out, "could not be consulted") {
			t.Fatalf("refusal message did not distinguish the never-consulted case; got:\n%s", out)
		}
		if strings.Contains(out, "status:") {
			t.Fatalf("refusal message fabricated a CI status with no HEAD resolved; got:\n%s", out)
		}
	})
}

// stubWorkflowCheckPerWorkflow answers differently per workflow, which is the
// only way to pin STATBUS-288's actual requirement: that the stale-template
// escape reads fast-tests and is NOT satisfied by pg_regress alone.
func stubWorkflowCheckPerWorkflow(t *testing.T, answers map[string]release.WorkflowCheckStatus) {
	t.Helper()
	old := checkWorkflowAtCommit
	checkWorkflowAtCommit = func(workflow, commit string) release.WorkflowCheckResult {
		status, ok := answers[workflow]
		if !ok {
			t.Errorf("escape consulted an unexpected workflow: %q", workflow)
			status = release.WorkflowCheckUnknown
		}
		return release.WorkflowCheckResult{Status: status, RunURL: "https://example.invalid/run/1", RunID: 1}
	}
	t.Cleanup(func() { checkWorkflowAtCommit = old })
}

// TestStaleTemplateBranchConsultsFastTests covers STATBUS-288.
//
// The stale-template refusal fires because the LOCAL suite ran against a
// template built from older migrations. Closing that gap needs evidence a suite
// actually EXECUTED against a database built from HEAD's migrations — and a
// green workflow run does not always mean that, because a run can ride an
// ancestor's stamp and still conclude "success".
//
// Observed on 2026-08-27 at a3988e163: fast-tests.yaml really ran (89/89), while
// pg_regress.yaml at the SAME commit was a stamp-ride from b319ae4be with zero
// tests executed. Both were green; only one was evidence. Gating a staleness
// check on the ride would defeat the check, since a ride proves a suite passed
// somewhere EARLIER — precisely the claim staleness disputes.
//
// The branch itself lives inside preflightChecks and is not unit-testable; this
// pins the verdict it switches on, for its exact call shape. Call-site polarity
// stays review-carried, as for every gate in that function.
func TestStaleTemplateBranchConsultsFastTests(t *testing.T) {
	const what = "latest migrations"
	drifted := "stamp's source-DB version 20260714100527 is behind HEAD's on-disk max 20260827163000"

	t.Run("fast-tests green covers the stale template", func(t *testing.T) {
		dir := newDriftRepo(t)
		stubWorkflowCheckPerWorkflow(t, map[string]release.WorkflowCheckStatus{
			release.WorkflowFastTests: release.WorkflowCheckGreen,
		})

		covered, ciResult := staleTemplateCoveredByFastTestsGreen(dir, what, drifted, false)
		if !covered {
			t.Fatal("a green fast-tests run at HEAD must cover a stale local template")
		}
		if ciResult.Status != release.WorkflowCheckGreen {
			t.Fatalf("returned status = %q, want green", ciResult.Status)
		}
		if _, err := os.Stat(fastTestStampPath(dir)); err != nil {
			t.Fatalf("escape path did not refresh the stamp: %v", err)
		}
	})

	// THE LOAD-BEARING ARM: pg_regress green, fast-tests NOT green. The escape
	// must refuse. If it consulted pg_regress it would pass here, and tonight's
	// evidence says that green can be an inherited ride.
	t.Run("pg_regress green alone does NOT satisfy it", func(t *testing.T) {
		dir := newDriftRepo(t)
		stubWorkflowCheckPerWorkflow(t, map[string]release.WorkflowCheckStatus{
			release.WorkflowFastTests: release.WorkflowCheckMissing,
			release.WorkflowPgRegress: release.WorkflowCheckGreen,
		})

		covered, _ := staleTemplateCoveredByFastTestsGreen(dir, what, drifted, false)
		if covered {
			t.Fatal("a pg_regress green must NOT satisfy the stale-template check — it can be a stamp-ride")
		}
		if _, err := os.Stat(fastTestStampPath(dir)); err == nil {
			t.Fatal("refusal wrote a local stamp")
		}
	})

	// Anything not green leaves the refusal standing — the genuinely
	// unverified case this gate exists for.
	for _, status := range []release.WorkflowCheckStatus{
		release.WorkflowCheckFailed,
		release.WorkflowCheckPending,
		release.WorkflowCheckMissing,
		release.WorkflowCheckUnknown,
	} {
		t.Run("fast-tests "+string(status)+" leaves the refusal standing", func(t *testing.T) {
			dir := newDriftRepo(t)
			stubWorkflowCheckPerWorkflow(t, map[string]release.WorkflowCheckStatus{
				release.WorkflowFastTests: status,
			})

			covered, ciResult := staleTemplateCoveredByFastTestsGreen(dir, what, drifted, false)
			if covered {
				t.Fatalf("fast-tests %s must NOT cover a stale local template", status)
			}
			// The caller prints ciResult, so a refusal must carry the status it
			// actually saw — otherwise the either/or message would read as
			// "CI was never consulted" when it plainly was.
			if ciResult.Status != status {
				t.Fatalf("returned status = %q, want %q", ciResult.Status, status)
			}
			if _, err := os.Stat(fastTestStampPath(dir)); err == nil {
				t.Fatal("refusal wrote a local stamp")
			}
		})
	}

	// The siblings must still ask pg_regress — the split is deliberate, not a
	// migration of every call site to fast-tests.
	t.Run("the file-drift siblings still ask pg_regress", func(t *testing.T) {
		dir := newDriftRepo(t)
		stubWorkflowCheckPerWorkflow(t, map[string]release.WorkflowCheckStatus{
			release.WorkflowPgRegress: release.WorkflowCheckGreen,
		})

		covered, _ := driftCoveredByCIGreen(dir, "test expected file drift", "test/expected/a.out", false)
		if !covered {
			t.Fatal("the file-drift escape must still be satisfied by a pg_regress green")
		}
	})

	t.Run("ride path still never persists", func(t *testing.T) {
		dir := newDriftRepo(t)
		stubWorkflowCheckPerWorkflow(t, map[string]release.WorkflowCheckStatus{
			release.WorkflowFastTests: release.WorkflowCheckGreen,
		})

		covered, _ := staleTemplateCoveredByFastTestsGreen(dir, what, drifted, true)
		if !covered {
			t.Fatal("green must still cover when the stamp came from a ride")
		}
		if _, err := os.Stat(fastTestStampPath(dir)); err == nil {
			t.Fatal("ride path wrote a local stamp — an inference must never become evidence")
		}
	})
}
