package cmd

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-316 absence-tolerance (found by CI, run 33275592180): a restored
// artifact can predate migration 20260829114700 (CI's restore path, and
// install.sh's seed-restore on a real box taking a pre-316 artifact), so
// public.normalize_all_sequences() genuinely does not exist yet at the
// completion-point CALL. normalizeAllSequences must check existence first
// and skip LOUDLY rather than fail the whole restore.
//
// Structural, not integration: this package has no live-DB-dependent Go
// tests (pg_regress is where DB behavior is proven in this codebase; a
// DB-dependent unit test here would break CI, which has no database for
// `go test`). The SQL primitive itself (to_regprocedure returns NULL, never
// raises, for an absent name) was verified empirically against a live
// database before this fix landed — this test pins the shape that makes
// that verification meaningful going forward: the check must run, and must
// run BEFORE the CALL that would otherwise fail on a pre-316 artifact.
func TestNormalizeAllSequencesChecksExistenceBeforeCalling_STATBUS316(t *testing.T) {
	b, err := os.ReadFile(thisRepoFile(t, "cli/cmd/sequence_normalize.go"))
	if err != nil {
		t.Fatalf("read sequence_normalize.go: %v", err)
	}
	src := string(b)
	start := strings.Index(src, "func normalizeAllSequences(")
	if start < 0 {
		t.Fatal("normalizeAllSequences not found — test is stale")
	}
	end := strings.Index(src[start:], "\n}\n")
	if end < 0 {
		t.Fatal("closing brace for normalizeAllSequences not found")
	}
	body := src[start : start+end]

	existsIdx := strings.Index(body, "to_regprocedure('public.normalize_all_sequences()')")
	callIdx := strings.Index(body, "\"CALL public.normalize_all_sequences();\"")
	if existsIdx < 0 || callIdx < 0 {
		t.Fatalf("missing the existence check or the CALL itself — test is stale (exists=%d call=%d)", existsIdx, callIdx)
	}
	if existsIdx > callIdx {
		t.Error(`the existence check must run BEFORE the CALL.

This is the exact CI failure (run 33275592180): a restored artifact can
predate migration 20260829114700, so the procedure genuinely does not exist
yet at this completion-point call. Checking after calling is too late — the
CALL itself already failed and returned the error this function exists to
avoid.`)
	}

	// The absence branch must return nil (proceed), never an error — a
	// pre-316 artifact restoring successfully with sequences left at
	// whatever positions it carried is exactly pre-316 behavior, not a
	// failure.
	absenceBranch := body[existsIdx:callIdx]
	if !strings.Contains(absenceBranch, "return nil") {
		t.Error(`the absence branch must "return nil" (proceed with the restore) — failing here would still block every restore of a pre-316 artifact, which is the bug this fix exists to remove`)
	}
	// And it must say so loudly (fmt.Printf/Println), not skip silently —
	// silent tolerance of a genuinely different code path (old artifact,
	// not yet normalized) is indistinguishable from a bug that quietly does
	// nothing.
	if !strings.Contains(absenceBranch, "fmt.Printf(") && !strings.Contains(absenceBranch, "fmt.Println(") {
		t.Error("the absence branch must print something (loud skip, not a silent one) before returning nil")
	}
}
