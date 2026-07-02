package upgrade

import (
	"context"
	"errors"
	"testing"
	"time"
)

// STATBUS-109 (doc-022) unit tests for the in-process backoff-retry machinery.
// The pure classifiers + the loop's gap/budget/clear/cancel logic are tested
// here Docker/DB-free; the end-to-end behaviour is the install-recovery arcs'
// job (STATBUS-071, the only behavioural oracle).

// ── classifyStepError (§5, the known-persistent list) ────────────────────────

func TestClassifyStepError_PersistentSignatures(t *testing.T) {
	persistent := []string{
		`ERROR: relation "public.foo" already exists (SQLSTATE 42P07)`,
		`ERROR: column "bar" does not exist`,
		`ERROR: null value in column "x" violates not-null constraint`,
		`ERROR: duplicate key value violates unique constraint "u"`,
		`ERROR: syntax error at or near "SLECT"`,
		`ERROR: cannot drop table t because other objects depend on it`,
		`ERROR: invalid input syntax for type integer`,
	}
	for _, msg := range persistent {
		if got := classifyStepMessage(msg); got != StepErrorPersistent {
			t.Errorf("deterministic failure must classify persistent-error: %q → %v", msg, got)
		}
		if got := classifyStepError(errors.New(msg)); got != StepErrorPersistent {
			t.Errorf("classifyStepError wrapper disagrees for %q → %v", msg, got)
		}
	}
}

func TestClassifyStepError_UnknownIsDefault(t *testing.T) {
	// Anything NOT recognised must default to unknown-error (do NOT silently
	// forward) — never mis-labelled persistent.
	unknown := []string{
		"connection reset by peer",
		"context deadline exceeded",
		"container healthcheck timed out waiting for rest",
		"",
	}
	for _, msg := range unknown {
		if got := classifyStepMessage(msg); got != StepErrorUnknown {
			t.Errorf("unrecognised failure must default to unknown-error: %q → %v", msg, got)
		}
	}
	// A nil error is not a failure to classify — guarded to Unknown, never a panic.
	if got := classifyStepError(nil); got != StepErrorUnknown {
		t.Errorf("classifyStepError(nil) must be unknown-error; got %v", got)
	}
}

func TestUnknownCauseString(t *testing.T) {
	cases := map[UnknownCause]string{
		CauseNone:             "none",
		CauseDBUnreachable:    "db-unreachable",
		CauseCommitNotFetched: "commit-not-fetched",
		CauseUnrecognized:     "unrecognized",
	}
	for c, want := range cases {
		if got := c.String(); got != want {
			t.Errorf("UnknownCause(%d).String() = %q, want %q", int(c), got, want)
		}
	}
}

// ── backoffRetry loop: clears / exhausts / cancels ───────────────────────────

// testService builds a Service whose only backoffRetry dependency (projDir, for
// emitHeartbeat's best-effort file write) is a temp dir.
func testService(t *testing.T) *Service {
	t.Helper()
	return &Service{projDir: t.TempDir()}
}

// fastSpec uses sub-millisecond gaps + a short budget so the loop logic is
// exercised without real backoff latency. name/probe supplied per case.
func fastSpec(name string, budget time.Duration, probe func(context.Context) error) retrySpec {
	return retrySpec{
		name:   name,
		gaps:   []time.Duration{1 * time.Millisecond, 2 * time.Millisecond},
		budget: budget,
		probe:  probe,
	}
}

func TestBackoffRetry_ClearsWhenProbeSucceeds(t *testing.T) {
	d := testService(t)
	var calls int
	spec := fastSpec("test-clear", time.Second, func(ctx context.Context) error {
		calls++
		if calls >= 3 { // fail twice, then clear
			return nil
		}
		return errors.New("still down")
	})
	if err := d.backoffRetry(context.Background(), spec); err != nil {
		t.Fatalf("backoffRetry must return nil once the probe clears; got %v", err)
	}
	if calls != 3 {
		t.Errorf("probe should have been called 3× (2 failures + 1 clear); got %d", calls)
	}
}

func TestBackoffRetry_ExhaustsToErrRetryExhausted(t *testing.T) {
	d := testService(t)
	var calls int
	spec := fastSpec("test-exhaust", 15*time.Millisecond, func(ctx context.Context) error {
		calls++
		return errors.New("permanently down")
	})
	err := d.backoffRetry(context.Background(), spec)
	if !errors.Is(err, ErrRetryExhausted) {
		t.Fatalf("a probe that never clears must return ErrRetryExhausted; got %v", err)
	}
	if calls < 2 {
		t.Errorf("expected multiple attempts before exhausting the budget; got %d", calls)
	}
}

func TestBackoffRetry_HonoursContextCancel(t *testing.T) {
	d := testService(t)
	ctx, cancel := context.WithCancel(context.Background())
	var calls int
	spec := retrySpec{
		name:   "test-cancel",
		gaps:   []time.Duration{50 * time.Millisecond},
		budget: time.Hour, // long budget → only cancellation can end it
		probe: func(ctx context.Context) error {
			calls++
			cancel() // cancel during the first probe → the sleep must abort
			return errors.New("down")
		},
	}
	err := d.backoffRetry(ctx, spec)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("backoffRetry must return ctx.Err() on cancellation; got %v", err)
	}
	if calls != 1 {
		t.Errorf("probe should run once then the cancelled ctx ends the loop; got %d calls", calls)
	}
}

// The db-unreachable spec must stay well inside WatchdogSec=120s per gap so the
// self-heartbeat cadence can never be starved (doc-022 §2 step 1); and the
// fetch spec's cap must be < WatchdogSec so a stall aborts before the watchdog.
func TestRetrySpecs_GapsStayInsideWatchdog(t *testing.T) {
	d := testService(t)
	for _, spec := range []retrySpec{d.dbUnreachableSpec(), d.commitNotFetchedSpec(nil, "deadbeef")} {
		for _, g := range spec.gaps {
			if g >= 120*time.Second {
				t.Errorf("%s gap %v must stay under WatchdogSec=120s", spec.name, g)
			}
		}
		if spec.budget <= 0 {
			t.Errorf("%s budget must be positive; got %v", spec.name, spec.budget)
		}
	}
	if fetchStallTimeout >= 120*time.Second {
		t.Errorf("fetchStallTimeout %v must be < WatchdogSec=120s so a stall aborts first", fetchStallTimeout)
	}
}
