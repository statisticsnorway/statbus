package upgrade

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"sync/atomic"
	"time"
)

// ─────────────────────────────────────────────────────────────────────────────
// STATBUS-109 — in-process backoff-retry for recovery (doc-022).
//
// When recovery cannot read its position because a KNOWN-INTERMITTENT condition
// holds (DB mid-restart, or the target commit not yet fetched), the old code
// EXITED and leaned on systemd restart as its retry — burning the StartLimit
// budget and risking a false unit-failure for a brief blip. The ratified model
// (doc/upgrade-recovery-model.md) replaces exit-on-transient with classify-then-
// act: retry the NAMED transient in-process; on exhaust, roll back (data-safe by
// construction now that STATBUS-110's read-only window blocks external writes
// across the danger phase); stop only on the genuinely UNKNOWN.
//
// Safe-by-default: we retry only what we can NAME as intermittent (the
// UnknownCause enum below) and roll back only what we can NAME as deterministic
// (classifyStepError); everything else is unknown → human stop.
// ─────────────────────────────────────────────────────────────────────────────

// UnknownCause types WHY a observed-state read returned ObservedPositionUnreadable, so the
// recovery dispatch can branch on a typed value instead of re-parsing a reason
// string (reach-for-types, doc-022 §1). The enum IS the curated known-
// intermittent list at the position-read surface: nothing reaches backoff-retry
// unless it was explicitly classified here.
type UnknownCause int

const (
	// CauseNone — not an Unknown verdict (AtTarget or Behind).
	CauseNone UnknownCause = iota
	// CauseDBUnreachable — the db.migration max-version query failed
	// (DB mid-restart). Known-intermittent → backoff-retry (db probe).
	CauseDBUnreachable
	// CauseCommitNotFetched — the target commit is absent from the local clone
	// (shallow/pruned). Known-intermittent → backoff-retry (fetch probe).
	CauseCommitNotFetched
	// CauseUnrecognized — an unrecognised position-read error (e.g. a
	// merge-base failure that is not exit-1 with the commit present). Unknown →
	// stop for a human.
	CauseUnrecognized
)

func (c UnknownCause) String() string {
	switch c {
	case CauseNone:
		return "none"
	case CauseDBUnreachable:
		return "db-unreachable"
	case CauseCommitNotFetched:
		return "commit-not-fetched"
	case CauseUnrecognized:
		return "unrecognized"
	default:
		return fmt.Sprintf("UnknownCause(%d)", int(c))
	}
}

// ErrRetryExhausted is returned by backoffRetry when the overall budget elapses
// with the probe still failing → the caller rolls back (data-safe via 110).
var ErrRetryExhausted = errors.New("backoff-retry exhausted")

// ErrFetchStalled is returned by fetchWithStallDetection when a fetch makes no
// output progress for fetchStallTimeout → this try is aborted as a stall (NOT a
// wall-clock deadline; a healthy slow transfer keeps emitting and runs on).
var ErrFetchStalled = errors.New("git fetch stalled (no progress)")

// heartbeatBeat bounds the silent window inside a backoff sleep: emit a systemd
// heartbeat at least this often so a gap approaching WatchdogSec=120s can never
// starve the watchdog. recoverFromFlag runs BEFORE the main-loop heartbeat
// ticker starts (service.go), so during recovery nothing else feeds the
// watchdog — the loop must self-heartbeat.
const heartbeatBeat = 30 * time.Second

// retrySpec parameterises backoffRetry for one known-intermittent cause
// (doc-022 §2). Only the probe and the backoff shape differ per cause; the loop,
// the per-iteration heartbeat, and the budget ceiling are shared.
type retrySpec struct {
	name   string                      // "db-unreachable" | "commit-not-fetched" — log + error text
	gaps   []time.Duration             // backoff sequence; the LAST value is the cap (reused after the list)
	budget time.Duration               // overall ceiling; on a failed try with elapsed >= budget → ErrRetryExhausted
	probe  func(context.Context) error // one attempt; nil == cleared (caller re-reads observed state)
}

// backoffRetry runs spec.probe on spec's backoff schedule until it clears
// (returns nil) or the budget is exhausted (returns ErrRetryExhausted), or ctx
// is cancelled (returns ctx.Err()). It emits a systemd heartbeat every iteration
// AND at least every heartbeatBeat during a sleep — CRITICAL because recovery
// runs before the main-loop heartbeat ticker, so nothing else keeps the
// WatchdogSec=120s deadline alive during the wait (doc-022 §2 step 1).
func (d *Service) backoffRetry(ctx context.Context, spec retrySpec) error {
	start := time.Now()
	for attempt := 0; ; attempt++ {
		emitHeartbeat(d.projDir) // self-heartbeat before the probe blocks
		err := spec.probe(ctx)
		if err == nil {
			fmt.Printf("recovery backoff-retry [%s]: cleared after %s (%d attempt(s))\n",
				spec.name, time.Since(start).Round(time.Second), attempt+1)
			return nil
		}
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ctxErr
		}
		elapsed := time.Since(start)
		fmt.Printf("recovery backoff-retry [%s]: attempt %d failed (%v); elapsed %s / budget %s\n",
			spec.name, attempt+1, err, elapsed.Round(time.Second), spec.budget)
		if elapsed >= spec.budget {
			return fmt.Errorf("%s: %w after %s (%d attempts)", spec.name, ErrRetryExhausted, elapsed.Round(time.Second), attempt+1)
		}
		gap := spec.gaps[len(spec.gaps)-1]
		if attempt < len(spec.gaps) {
			gap = spec.gaps[attempt]
		}
		if err := d.heartbeatingSleep(ctx, gap); err != nil {
			return err
		}
	}
}

// heartbeatingSleep sleeps for total, emitting a systemd heartbeat at least
// every heartbeatBeat so a gap near WatchdogSec never starves the watchdog, and
// returns early with ctx.Err() if ctx is cancelled.
func (d *Service) heartbeatingSleep(ctx context.Context, total time.Duration) error {
	deadline := time.Now().Add(total)
	for {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return nil
		}
		emitHeartbeat(d.projDir)
		wait := heartbeatBeat
		if remaining < wait {
			wait = remaining
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(wait):
		}
	}
}

// recoveryBackoffBudgetFloor guards the STATBUS_RECOVERY_BACKOFF_BUDGET override:
// a value below this is clamped up (+ a WARN), so a fat-fingered override cannot
// make the backoff exhaust mid-legitimate-blip. 1s is low enough for the
// transient-backoff arcs to exercise the RESOLVES + EXHAUST arms in SECONDS (the
// load-bearing test criterion) yet non-zero.
const recoveryBackoffBudgetFloor = 1 * time.Second

// resolveBackoffBudget returns the effective backoff-retry budget: the
// STATBUS_RECOVERY_BACKOFF_BUDGET override (a Go duration string, e.g. "30s")
// when valid and >= the floor, else the per-spec production default. Same house
// pattern as resolveMigrateUpTimeout (watchdog.go) — read fresh so the arc can
// arm seconds via a restart-for-env dropin; every non-default path WARNs so the
// arc log shows exactly which budget is in force. No-op in production (env unset).
func resolveBackoffBudget(defaultBudget time.Duration) time.Duration {
	raw := os.Getenv("STATBUS_RECOVERY_BACKOFF_BUDGET")
	if raw == "" {
		return defaultBudget
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		fmt.Fprintf(os.Stderr, "WARN: STATBUS_RECOVERY_BACKOFF_BUDGET=%q is not a valid Go duration (%v) — using the default %s\n", raw, err, defaultBudget)
		return defaultBudget
	}
	if d < recoveryBackoffBudgetFloor {
		fmt.Fprintf(os.Stderr, "WARN: STATBUS_RECOVERY_BACKOFF_BUDGET=%s is below the floor %s — clamping to the floor\n", d, recoveryBackoffBudgetFloor)
		return recoveryBackoffBudgetFloor
	}
	return d
}

// dbUnreachableSpec is the backoff-retry for CauseDBUnreachable (doc-022 §2). The
// probe RECONNECTS the service's sessions (reconnect closes the dead conns,
// re-establishes queryConn/listenConn, re-acquires the advisory lock — the
// upgrade-actor mutex the old exit-restart re-took on the fresh process — and
// re-applies the STATBUS-110 read-only self-exempt), then a trivial SELECT 1
// confirms the DB is actually reachable. On clear, queryConn is live +
// write-enabled for the immediate observed-state re-read. A 5s per-try timeout
// keeps each attempt a quick check, never a transfer.
func (d *Service) dbUnreachableSpec() retrySpec {
	return retrySpec{
		name:   "db-unreachable",
		gaps:   []time.Duration{1 * time.Second, 2 * time.Second, 4 * time.Second, 8 * time.Second, 16 * time.Second, 30 * time.Second},
		budget: resolveBackoffBudget(5 * time.Minute),
		probe: func(ctx context.Context) error {
			probeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			defer cancel()
			if err := d.reconnect(probeCtx); err != nil {
				return err
			}
			var one int
			return d.queryConn.QueryRow(probeCtx, "SELECT 1").Scan(&one)
		},
	}
}

// commitNotFetchedSpec was the backoff-retry for CauseCommitNotFetched — DELETED
// (STATBUS-071, architect ruling 2026-07-15) as orphaned machinery: its ONLY
// dispatch caller (the resuming classify-then-act arm) was retired because the
// cause is structurally unreachable at that site (three invariants — see the
// retirement note at service.go's resuming switch). fetchWithStallDetection is
// KEPT: it still has a live caller on the FORWARD fetch path (service.go:5390,
// the stall-not-deadline fetch that replaced a wall-clock deadline), so only the
// spec wrapper — never the fetch machinery — goes with the dead dispatch arm.

// fetchStallTimeout is the per-try no-progress window: a fetch that emits no
// output line for this long is aborted as a stall. 60s < WatchdogSec=120s, so
// the stall abort always fires before the watchdog would.
const fetchStallTimeout = 60 * time.Second

// fetchStallPoll is how often the stall watchdog checks the progress timestamp.
const fetchStallPoll = 5 * time.Second

// fetchWithStallDetection runs `git fetch origin <commitSHA>` with STALL
// detection instead of a wall-clock deadline (doc-022 §3). Every line of git
// output advances a progress timestamp AND feeds the systemd watchdog
// (emitHeartbeat); a watchdog goroutine cancels the fetch ONLY if no progress
// appears for fetchStallTimeout. Returns nil on success, ErrFetchStalled on a
// stall, or the underlying git error otherwise.
func (d *Service) fetchWithStallDetection(ctx context.Context, logWriter io.Writer, commitSHA string) error {
	ctx, cancel := context.WithCancel(ctx) // NOT WithTimeout — no deadline; the caller owns cancellation
	defer cancel()

	var lastProgressNano atomic.Int64
	lastProgressNano.Store(time.Now().UnixNano())
	onAdvance := func() {
		lastProgressNano.Store(time.Now().UnixNano())
		emitHeartbeat(d.projDir) // a transferring fetch keeps the watchdog alive; a stall stops both
	}

	var stalled atomic.Bool
	go func() {
		ticker := time.NewTicker(fetchStallPoll)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				last := time.Unix(0, lastProgressNano.Load())
				if time.Since(last) > fetchStallTimeout {
					stalled.Store(true)
					cancel() // abort THIS try (a stall, not a deadline)
					return
				}
			}
		}
	}()

	err := runCommandToLogCtx(ctx, d.projDir, logWriter, "git", onAdvance, "git", "fetch", "origin", commitSHA)
	if stalled.Load() {
		return fmt.Errorf("git fetch %s: %w after %s", ShortForDisplay(commitSHA), ErrFetchStalled, fetchStallTimeout)
	}
	return err
}

// ─────────────────────────────────────────────────────────────────────────────
// The known-PERSISTENT list (doc-022 §5, AC#3, the smaller half).
//
// The position-read surface produces no deterministic errors (a read-only
// SELECT MAX(version) never hits "already exists"). Persistent errors arise on
// the forward STEP — migrate up inside resumeNewSb/applyNewSbUpgrading, which
// already rolls back on failure today. classifyStepError makes that
// classification explicit + safe-by-default: a RECOGNISED deterministic error is
// named persistent (roll back, zero retries — current behaviour); anything
// UNRECOGNISED is unknown-by-default and must NOT be silently forwarded.
// ─────────────────────────────────────────────────────────────────────────────

// StepErrorClass classifies a forward-step (migrate up) failure.
type StepErrorClass int

const (
	// StepErrorUnknown — the DEFAULT: an unrecognised forward-step error. Under
	// the ratified model this must not be silently forwarded; it is surfaced as
	// the human `unknown` stop.
	StepErrorUnknown StepErrorClass = iota
	// StepErrorPersistent — a recognised deterministic failure (a re-run cannot
	// help). Roll back, zero retries.
	StepErrorPersistent
)

func (c StepErrorClass) String() string {
	switch c {
	case StepErrorPersistent:
		return "persistent-error"
	default:
		return "unknown-error"
	}
}

// persistentStepSignatures is the curated match set of deterministic migrate/
// forward-step failures (PG SQLSTATE-class substrings + known deterministic
// signatures). A migrate up that trips one of these cannot be helped by a
// re-run → roll back. Everything NOT here is unknown-by-default. Kept small and
// concrete on purpose — over-building a retry story around the deterministic
// subprocess migrate is out of scope (doc-022 §5 scope note).
var persistentStepSignatures = []string{
	"already exists",
	"does not exist",
	"violates",   // *_violates_* constraint / not-null / foreign-key / check
	"constraint", // constraint violations phrased without "violates"
	"duplicate key",
	"syntax error",
	"undefined", // undefined column/table/function
	"cannot",    // "cannot drop ...", "cannot alter ..."
	"invalid input",
}

// classifyStepError names a forward-step failure Persistent (recognised
// deterministic) or Unknown (default — do not silently forward). Pure —
// unit-tested.
func classifyStepError(err error) StepErrorClass {
	if err == nil {
		return StepErrorUnknown // a nil error is not a failure to classify; caller shouldn't call this
	}
	return classifyStepMessage(err.Error())
}

// classifyStepMessage is classifyStepError over a raw message string (the
// forward-step failure narrative is a formatted string at its handler, not an
// error value). Same curated match set. Pure — unit-tested.
func classifyStepMessage(msg string) StepErrorClass {
	m := strings.ToLower(msg)
	for _, sig := range persistentStepSignatures {
		if strings.Contains(m, sig) {
			return StepErrorPersistent
		}
	}
	return StepErrorUnknown
}
