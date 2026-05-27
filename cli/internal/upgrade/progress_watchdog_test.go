package upgrade

import (
	"io"
	"testing"
	"time"
)

// #3 progress-gated watchdog seam (plan upgrade-resume-structural-whole.md piece #3).
// The active-phase WATCHDOG=1 ticker must ping ONLY IF the pipeline advanced
// within stallThreshold. "Advance" is recorded on ProgressLog.lastAdvanceAt,
// bumped by (a) ProgressLog.Write (step boundaries) and (b) a PrefixWriter
// onLine callback (every subprocess output line). These guards pin the seam:
// the bump primitives exist and fire from both sources. The ticker-gating +
// migrate PID-alive bump + thresholds are exercised by the harness + the
// ticker guard; this file pins the bump infrastructure that all of it rests on.

// TestProgressLog_BumpAdvancesClock: bump() makes sinceLastAdvance() small;
// without a bump it grows. (No real sleep dependence — assert monotonic.)
func TestProgressLog_BumpAdvancesClock(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.bump()
	if d := p.sinceLastAdvance(); d > time.Second {
		t.Errorf("sinceLastAdvance right after bump should be ~0, got %v", d)
	}
}

// TestProgressLog_WriteBumps: ProgressLog.Write (a step boundary) advances
// lastAdvanceAt — the (a) bump source.
func TestProgressLog_WriteBumps(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	// Force the clock back so we can see Write move it forward.
	p.setLastAdvanceForTest(time.Now().Add(-10 * time.Minute))
	if d := p.sinceLastAdvance(); d < 5*time.Minute {
		t.Fatalf("setup: expected a stale clock, got %v", d)
	}
	p.Write("a step boundary")
	if d := p.sinceLastAdvance(); d > time.Second {
		t.Errorf("ProgressLog.Write must bump lastAdvanceAt (step-boundary advance); sinceLastAdvance=%v", d)
	}
}

// TestPrefixWriter_OnLineFiresPerLine: the onLine callback fires once per
// newline-terminated line — the (b) subprocess-output bump source.
func TestPrefixWriter_OnLineFiresPerLine(t *testing.T) {
	var n int
	w := NewPrefixWriter("O", "migrate", io.Discard, func() { n++ })
	w.Write([]byte("line one\nline two\n"))
	if n != 2 {
		t.Errorf("onLine should fire once per newline (2 lines), got %d", n)
	}
	// A partial line (no newline) does not fire until flushed.
	w.Write([]byte("partial"))
	if n != 2 {
		t.Errorf("partial line (no newline) must NOT fire onLine yet, got %d", n)
	}
	w.Flush()
	if n != 3 {
		t.Errorf("Flush of a buffered partial line must fire onLine, got %d", n)
	}
}

// TestPrefixWriter_NilOnLineSafe: a nil onLine (non-tracked callers) must not panic.
func TestPrefixWriter_NilOnLineSafe(t *testing.T) {
	w := NewPrefixWriter("O", "git", io.Discard, nil)
	w.Write([]byte("no callback here\n"))
	w.Flush()
}
