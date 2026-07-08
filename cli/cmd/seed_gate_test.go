package cmd

import (
	"errors"
	"fmt"
	"strings"
	"testing"
)

// TestInterpretAppliedMigrationsProbe pins the STATBUS-018 probe matrix for the
// applied-migrations gate (dbHasAppliedMigrations). The pure verdict is factored
// out of the psql shell-out so the three DB states are unit-testable without a
// live database — the classifyAdvisoryHolder / classifySessions pattern in this
// package. The (output, error) pairs below are exactly what psql produces for
// each DB state:
//   - missing db.migration table → psql errors (relation does not exist) → the
//     probe's cmd.Output returns non-nil → NOT migrated (seed still winnable).
//   - table present but empty (ensureMigrationTable ran, no migration applied) →
//     "f" → NOT migrated (no eras yet, seed still winnable).
//   - table present with >= 1 applied row → "t" → migrated (seed would collide
//     with the sql_saga updatable-view triggers).
func TestInterpretAppliedMigrationsProbe(t *testing.T) {
	cases := []struct {
		name string
		out  string
		err  error
		want bool
	}{
		{"missing table (probe errors) → not migrated", "", errors.New(`ERROR:  relation "db.migration" does not exist`), false},
		{"empty table → not migrated (seed still winnable)", "f", nil, false},
		{"has applied row → migrated (seed would collide)", "t", nil, true},
		{"whitespace around t is tolerated", " t \n", nil, true},
		{"whitespace around f is tolerated", " f \n", nil, false},
		{"unexpected output → not migrated (conservative fresh-favouring default)", "banana", nil, false},
		{"probe error dominates any stale output", "t", errors.New("connection refused"), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := interpretAppliedMigrationsProbe(c.out, c.err); got != c.want {
				t.Errorf("interpretAppliedMigrationsProbe(%q, %v) = %v, want %v", c.out, c.err, got, c.want)
			}
		})
	}
}

// TestStepRunOutcomeNeverDoneOnError pins the STATBUS-018 loudness invariant:
// the install loop's reported outcome is NEVER "DONE" for a non-nil restore
// error. A swallowed seed restore that reads as success is the exact silent
// ~10x-slowdown class this ticket closes. stepRunOutcome is the pure guard the
// loop routes every run() error through.
func TestStepRunOutcomeNeverDoneOnError(t *testing.T) {
	// Success is the ONLY path to DONE.
	if line, fatal := stepRunOutcome(nil); line != "DONE" || fatal {
		t.Errorf("nil err must be (DONE, false); got (%q, %v)", line, fatal)
	}

	// A failed restore (loud, non-fatal) — must degrade, never DONE — including
	// when the sentinel is wrapped.
	for _, err := range []error{errSeedFallback, fmt.Errorf("wrapped: %w", errSeedFallback)} {
		line, fatal := stepRunOutcome(err)
		if fatal {
			t.Errorf("errSeedFallback must be non-fatal (degrade to full migrations); got fatal for %v", err)
		}
		if line == "DONE" {
			t.Errorf("STATBUS-018: a restore error must NEVER report DONE; got DONE for %v", err)
		}
		if !strings.Contains(line, "falling back") {
			t.Errorf("the fallback report must name the fallback; got %q", line)
		}
	}

	// No seed image (calm, non-fatal) — must degrade, never DONE.
	for _, err := range []error{errSeedUnavailable, fmt.Errorf("wrapped: %w", errSeedUnavailable)} {
		line, fatal := stepRunOutcome(err)
		if fatal {
			t.Errorf("errSeedUnavailable must be non-fatal; got fatal for %v", err)
		}
		if line == "DONE" {
			t.Errorf("no-seed-image must not report DONE; got DONE for %v", err)
		}
	}

	// Any other error is fatal: the loop prints "FAILED: <err>" and halts —
	// which is also never DONE.
	if _, fatal := stepRunOutcome(errors.New("disk full")); !fatal {
		t.Error("a non-seed error must be fatal (halts the install)")
	}
}
