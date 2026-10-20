package cmd

import (
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"testing"
)

func TestClassifySeedRestoreErrorFallsBackForIncompatibleCache(t *testing.T) {
	cmd := exec.Command("sh", "-c", fmt.Sprintf("exit %d", ExitSeedIncompatible))
	err := cmd.Run()
	if err == nil {
		t.Fatal("expected synthetic incompatible-cache subprocess failure")
	}
	if got := classifySeedRestoreError(err); !errors.Is(got, errSeedFallback) {
		t.Fatalf("incompatible cache must map to full migration fallback, got %v", got)
	}
	if got := classifySeedRestoreError(errors.New("pg_restore failed")); !errors.Is(got, errSeedFallback) {
		t.Fatalf("genuine restore failure must also map to full migration fallback, got %v", got)
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
