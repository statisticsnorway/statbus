package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
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

			got := driftCoveredByCIGreen(dir, "test expected file drift", "test/expected/a.out", false)
			if got != tc.want {
				t.Fatalf("pg_regress %s: escape returned %v, want %v", tc.status, got, tc.want)
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

	if !driftCoveredByCIGreen(dir, "latest migrations", "migrations/20260101000000_seed.up.sql", false) {
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

	if !driftCoveredByCIGreen(dir, "latest migrations", "migrations/20260101000000_seed.up.sql", true) {
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

	if driftCoveredByCIGreen(dir, "latest migrations", "migrations/x.up.sql", false) {
		t.Fatal("escape passed with no HEAD — a check that examines nothing must refuse")
	}
}
