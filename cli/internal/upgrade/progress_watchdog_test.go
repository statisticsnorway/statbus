package upgrade

import (
	"context"
	"io"
	"sync/atomic"
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

// #3 (b) gate: the applyNewSbUpgrading WATCHDOG=1 ticker pings ONLY IF
// shouldPingWatchdog(stallThreshold) is true:
//   advancing (sinceLastAdvance < stallThreshold) → ping (step is alive)
//   stalled (>= stallThreshold) → NO ping → WatchdogSec fires (hung, caught)
//   EXCEPT deferGating set (the migrate/recreate step, bounded by its own
//   runCommandToLog timeout) → always ping.
// These guards pin the gate decision (pure, no systemd).

func TestShouldPingWatchdog_AdvancingPings(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.bump() // just advanced
	if !p.shouldPingWatchdog(3 * time.Minute) {
		t.Error("an advancing pipeline (sinceLastAdvance < stallThreshold) must PING the watchdog")
	}
}

func TestShouldPingWatchdog_StalledDoesNotPing(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.setLastAdvanceForTest(time.Now().Add(-5 * time.Minute)) // no advance for 5min
	if p.shouldPingWatchdog(3 * time.Minute) {
		t.Error("a stalled pipeline (sinceLastAdvance >= stallThreshold) must NOT ping — WatchdogSec must fire (hung→caught)")
	}
}

func TestShouldPingWatchdog_DeferOverridesStall(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.setLastAdvanceForTest(time.Now().Add(-5 * time.Minute)) // stalled by output measure
	p.setDeferGating(true)                                    // but inside the migrate step
	if !p.shouldPingWatchdog(3 * time.Minute) {
		t.Error("deferGating (migrate/recreate step, bounded by its own runCommandToLog timeout) must PING despite output-silence — the step's own timeout + #7 bound a hang, NOT the watchdog")
	}
	p.setDeferGating(false)
	if p.shouldPingWatchdog(3 * time.Minute) {
		t.Error("clearing deferGating must restore output-gating (stalled → no ping)")
	}
}

// #3 (b) ticker: runGatedWatchdogTicker is the single applyNewSbUpgrading watchdog
// goroutine. It pings ONLY when progress.shouldPingWatchdog(stall) is true —
// collapsing the prior two unconditional tickers (reconnect + applyNewSbUpgrading)
// into one progress-gated loop. A hung step (no advance) stops the pings so
// WatchdogSec fires; a live or migrate-deferred step keeps pinging. These
// guards drive the loop with a fast cadence + an injected ping counter (no
// systemd) and assert the gate is consulted per tick + ctx cancellation reaps
// the goroutine.

// pollUntil spins until cond() or the deadline, so we don't depend on exact
// ticker timing (avoids a flaky sleep-then-assert).
func pollUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("timed out waiting for: %s", what)
}

func TestRunGatedWatchdogTicker_AdvancingPings(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.bump() // advancing
	var pings atomic.Int64
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	// Long stall threshold so "advancing" stays true; fast cadence so ticks fly.
	go runGatedWatchdogTicker(ctx, p, time.Hour, time.Millisecond, func() { pings.Add(1) }, done)
	pollUntil(t, "an advancing pipeline to ping the watchdog at least twice", func() bool {
		// keep it advancing so the gate stays open
		p.bump()
		return pings.Load() >= 2
	})
	cancel()
	<-done
}

func TestRunGatedWatchdogTicker_StalledSkips(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.setLastAdvanceForTest(time.Now().Add(-time.Hour)) // stalled
	var pings atomic.Int64
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	// stall threshold 1ms ⇒ already stalled; the loop must NOT ping.
	go runGatedWatchdogTicker(ctx, p, time.Millisecond, time.Millisecond, func() { pings.Add(1) }, done)
	// Give the loop many cadence intervals to (wrongly) ping.
	time.Sleep(50 * time.Millisecond)
	cancel()
	<-done
	if got := pings.Load(); got != 0 {
		t.Errorf("a stalled pipeline must NOT ping (WatchdogSec must fire); got %d pings", got)
	}
}

func TestRunGatedWatchdogTicker_DeferPings(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.setLastAdvanceForTest(time.Now().Add(-time.Hour)) // output-stalled
	p.setDeferGating(true)                              // but inside migrate/recreate
	var pings atomic.Int64
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go runGatedWatchdogTicker(ctx, p, time.Millisecond, time.Millisecond, func() { pings.Add(1) }, done)
	pollUntil(t, "deferGating to keep pinging despite output-silence", func() bool {
		return pings.Load() >= 2
	})
	cancel()
	<-done
}

func TestRunGatedWatchdogTicker_CtxCancelStops(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.bump()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go runGatedWatchdogTicker(ctx, p, time.Hour, time.Millisecond, func() {}, done)
	cancel()
	select {
	case <-done:
		// good — ctx cancellation reaped the goroutine and closed done.
	case <-time.After(2 * time.Second):
		t.Fatal("runGatedWatchdogTicker must close done on ctx cancellation (goroutine leak)")
	}
}

// TestRunGatedWatchdogTicker_NilProgressPings: a nil ProgressLog (untracked
// caller) pings unconditionally — shouldPingWatchdog(nil)==true — preserving
// the prior unconditional behaviour for any non-tracked use.
func TestRunGatedWatchdogTicker_NilProgressPings(t *testing.T) {
	var pings atomic.Int64
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go runGatedWatchdogTicker(ctx, nil, time.Millisecond, time.Millisecond, func() { pings.Add(1) }, done)
	pollUntil(t, "a nil ProgressLog to ping unconditionally", func() bool {
		return pings.Load() >= 2
	})
	cancel()
	<-done
}
