package cmd

// STATBUS-233: the immutability gate must REFUSE to compare migrations against a
// predecessor tag that is not an ancestor of HEAD.
//
// Git diffs any two commits, related or not, and returns a confident-looking
// answer. Against a predecessor HEAD never descended from, that answer lists
// every re-committed migration as "modified" — a flood in which a genuine
// post-release edit is invisible.
//
// Both directions of that verdict are harmful, which is why the gate must answer
// neither: the flood trains an operator to bless past the gate, and a single
// blanket bless baselines a corpus nobody read.
//
// STATBUS-239 — CORRECTION TO THIS FILE'S ORIGINAL PREMISE. It used to state as
// fact that the repository was rebaselined on 2026-07-14 with 77fa16fb2 as the
// root, leaving pre-rebaseline tags disconnected. That never happened. The
// clone we measured in was SHALLOW, and every "disconnected" reading was the
// shallow boundary answering instead of the history: in a full clone
// 77fa16fb2 has a parent (bab043771), the true root is 898d04734, and
// v2026.05.5 IS an ancestor of HEAD (GitHub compare: ahead 2154, behind 0).
//
// The HAZARD the fixtures below exercise is unaffected — a predecessor tag off
// this line of history is still a thing git will happily diff, and the gate
// must still refuse it. Only the claim that THIS repo was in that state was
// false. The real-repo arm that asserted it has been replaced by the guard
// against the condition that produced the false reading: a shallow clone.

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// disconnectedTagFixture builds a repo with a migration and a tag on an ORPHAN
// branch — a tag that exists, resolves, and shares no ancestry with HEAD. That
// is the shape the rebaseline left behind, in miniature.
func disconnectedTagFixture(t *testing.T, tag string) string {
	t.Helper()
	dir := makeRepo(t)

	// An orphan branch has no parent, so nothing on it is an ancestor of master.
	runGitInCmd(t, dir, "checkout", "--orphan", "discarded-history")
	runGitInCmd(t, dir, "rm", "-rf", "--cached", ".")
	migDir := filepath.Join(dir, "migrations")
	if err := os.MkdirAll(migDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(migDir, "20260101000000_init.up.sql"), []byte("-- old-history init\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runGitInCmd(t, dir, "add", ".")
	runGitInCmd(t, dir, "commit", "-q", "-m", "pre-rebaseline root")
	tagAnnotated(t, dir, tag, "pre-rebaseline stable "+tag)

	// Back to the real line of history. Nothing here descends from that tag.
	runGitInCmd(t, dir, "checkout", "-q", "master")
	return dir
}

// TestTagIsAncestorOfHEAD_STATBUS233 pins the primitive the gate rests on: a
// disconnected tag is reported as NOT an ancestor, WITHOUT an error — the
// distinction matters, because the gate refuses differently for "the answer is
// no" than for "I could not tell".
func TestTagIsAncestorOfHEAD_STATBUS233(t *testing.T) {
	t.Run("disconnected tag: not an ancestor, no error", func(t *testing.T) {
		dir := disconnectedTagFixture(t, "v2026.05.5")
		connected, err := tagIsAncestorOfHEAD(dir, "v2026.05.5")
		if err != nil {
			t.Fatalf("a disconnected tag is a clean NO, not an error: %v", err)
		}
		if connected {
			t.Error("a tag on an orphan branch was reported as an ancestor of HEAD — the whole refusal rests on this answer")
		}
	})

	t.Run("connected tag: is an ancestor", func(t *testing.T) {
		dir := makeRepo(t)
		tagAnnotated(t, dir, "v2026.08.0", "connected stable")
		// A later commit ON THIS LINE, so the tag is a strict ancestor.
		if err := os.WriteFile(filepath.Join(dir, "migrations", "20260202000000_later.up.sql"), []byte("-- later\n"), 0644); err != nil {
			t.Fatal(err)
		}
		gitAddCommit(t, dir, "later work")

		connected, err := tagIsAncestorOfHEAD(dir, "v2026.08.0")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !connected {
			t.Error("a tag on this history's own line was reported as NOT an ancestor — that would refuse every legitimate comparison")
		}
	})

	t.Run("absent tag: an error, never a silent false", func(t *testing.T) {
		dir := makeRepo(t)
		if _, err := tagIsAncestorOfHEAD(dir, "v2026.01.0"); err == nil {
			t.Error("a missing tag must be an ERROR — reporting it as 'not an ancestor' would let a typo read as a disconnection")
		}
	})
}

// TestImmutabilityGate_RefusesDisconnectedPredecessor_STATBUS233 is the gate-level
// arm (AC#1, AC#2). RED before the fix: the gate compared against the orphan tag
// and printed a per-file "modified" flood as though it were a verdict.
func TestImmutabilityGate_RefusesDisconnectedPredecessor_STATBUS233(t *testing.T) {
	dir := disconnectedTagFixture(t, "v2026.05.5")

	var passed bool
	out := captureStdout(t, func() {
		passed = checkImmutabilityGateAgainst(dir, "v2026.05.5")
	})

	if passed {
		t.Fatalf("the gate PASSED while comparing against a disconnected tag — a diff across unrelated histories is noise, and presenting it as a verdict is what STATBUS-233 removes; output:\n%s", out)
	}
	if !strings.Contains(out, "NOT an ancestor of HEAD") {
		t.Errorf("the refusal must say the tag is not an ancestor — that is the actual reason; output:\n%s", out)
	}
	if !strings.Contains(out, "v2026.05.5") {
		t.Errorf("the refusal must NAME the tag (AC#2); output:\n%s", out)
	}
	if !strings.Contains(out, "merge-base --is-ancestor") {
		t.Errorf("the refusal must give the operator the command that verifies the claim; output:\n%s", out)
	}
	if !strings.Contains(out, "promote the first stable") {
		t.Errorf("the refusal must name the remedy — the state heals once a stable exists in this history; output:\n%s", out)
	}
	// The flood must NOT appear: no per-file "modified" lines masquerading as findings.
	if strings.Contains(out, "20260101000000") {
		t.Errorf("the gate listed migrations from the disconnected tree — it must refuse BEFORE diffing, or the flood is exactly what the operator sees; output:\n%s", out)
	}
}

// TestImmutabilityGate_ConnectedPredecessorStillCompares_STATBUS233 is AC#3's
// positive control: the refusal must not swallow the cases that work. A connected
// predecessor with a MODIFIED released migration must still be caught.
func TestImmutabilityGate_ConnectedPredecessorStillCompares_STATBUS233(t *testing.T) {
	dir := immutabilityFixture(t, "v2026.08.0") // tags, then edits the released migration
	t.Setenv("STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION", "")

	var passed bool
	out := captureStdout(t, func() {
		passed = checkImmutabilityGateAgainst(dir, "v2026.08.0")
	})

	if passed {
		t.Fatalf("a MODIFIED released migration against a CONNECTED predecessor must still fail the gate — 233 must not turn the check off; output:\n%s", out)
	}
	if strings.Contains(out, "NOT an ancestor of HEAD") {
		t.Errorf("a connected predecessor was wrongly refused as disconnected — that would break every legitimate comparison; output:\n%s", out)
	}
}

// TestRealRepo_NotShallow_STATBUS239 replaces the AC#4 canary that asserted the
// rebaseline. It guards the PRECONDITION every history-dependent check we own
// rests on: that this clone actually contains the history it is about to reason
// over.
//
// A shallow clone does not error when asked about commits beyond its boundary —
// it answers as though they do not exist. `merge-base --is-ancestor` exits 1,
// `rev-list --max-parents=0` names the graft point as the root, and both
// readings look exactly like a genuine disconnection. That is precisely how
// STATBUS-233's premise came to be false: the instrument was believed, the
// history was never examined.
//
// So the assertion is deliberately about the CLONE, not about any tag: a check
// that cannot examine history must not report a pass about history. Flipping the
// old arm to assert "v2026.05.5 IS an ancestor" would have pinned the same
// confusion the other way up — in a shallow clone that assertion fails while
// nothing about the repository is wrong.
//
// CI is green on arrival by construction: go-test.yaml's go-test job checks out
// with fetch-depth: 0.
func TestRealRepo_NotShallow_STATBUS239(t *testing.T) {
	repo := thisRepoFile(t, ".")

	out, err := exec.Command("git", "-C", repo, "rev-parse", "--is-shallow-repository").CombinedOutput()
	if err != nil {
		t.Fatalf("git rev-parse --is-shallow-repository in %s: %v\n%s", repo, err, out)
	}
	shallow := strings.TrimSpace(string(out))

	if shallow != "false" {
		t.Fatalf("this clone is SHALLOW (git rev-parse --is-shallow-repository = %q).\n"+
			"Every history-dependent check in this package — the immutability gate's\n"+
			"ancestry refusal, migration diffs against a predecessor tag, seed ancestor\n"+
			"selection — will read the shallow boundary as a fact about the repository\n"+
			"and answer confidently with it. That is STATBUS-239: a tag that IS an\n"+
			"ancestor was reported as disconnected, and the wrong fact was written down.\n"+
			"Fix: git fetch --unshallow", shallow)
	}
}
