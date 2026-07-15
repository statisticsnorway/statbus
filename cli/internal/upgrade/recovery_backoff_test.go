package upgrade

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"
)

// STATBUS-109 (doc-022) unit tests for the in-process backoff-retry machinery.
// The pure classifiers + the loop's gap/budget/clear/cancel logic are tested
// here Docker/DB-free; the end-to-end behaviour is the install-recovery arcs'
// job (STATBUS-071, the only behavioural oracle).

// TestClassifyPathReadsBounded pins STATBUS-190: EVERY DB read on the recovery
// classify path (recoverFromFlag entry → backoff engagement) is bounded by the ONE
// shared recoveryReadTimeout, and the observed-state read's error classifies as
// CauseDBUnreachable — so a paused/frozen DB (which HANGS a live-but-unanswering
// conn) and a fast connection-refusal are ONE class routed to the in-process
// backoff, never a wedge before backoff engages (the run-2 finding).
//
// STRUCTURAL, not behavioural: a live-but-broken *pgx.Conn (the "refused/hung DB"
// state) is not constructible DB-free — pgx.Connect to a dead address returns no
// conn, and the package deliberately avoids DB-needing Go tests (STATBUS-182). So
// the boundedness + the single-class classification are pinned here; the runtime
// hang→backoff behaviour is the transient-db-backoff arc's oracle (it keeps
// docker-pause as the stronger inducement).
func TestClassifyPathReadsBounded(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	source := string(src)

	// (1) loadLogRelPath — the FIRST classify-path read — bounds with the shared
	// const and uses the bounded ctx (not the raw ctx) for its QueryRow.
	logBody := extractFuncBody(t, source, "func (d *Service) loadLogRelPath(")
	if !strings.Contains(logBody, "context.WithTimeout(ctx, recoveryReadTimeout)") {
		t.Error("loadLogRelPath must bound its read with recoveryReadTimeout (STATBUS-190) — an unbounded read on a paused DB hangs the classify path before backoff engages")
	}
	if strings.Contains(logBody, "QueryRow(ctx,") {
		t.Error("loadLogRelPath must pass the bounded readCtx (not the raw ctx) to QueryRow")
	}

	// (2) verifyUpgradeObservedStateEx — the db.migration read — bounds with the
	// SAME const, and its error classifies CauseDBUnreachable (hang == refusal).
	verifyBody := extractFuncBody(t, source, "func (d *Service) verifyUpgradeObservedStateEx(")
	if !strings.Contains(verifyBody, "context.WithTimeout(ctx, recoveryReadTimeout)") {
		t.Error("verifyUpgradeObservedStateEx must bound the db.migration read with recoveryReadTimeout (STATBUS-190)")
	}
	if strings.Contains(verifyBody, "QueryRow(ctx,") {
		t.Error("the db.migration read must pass the bounded readCtx (not the raw ctx)")
	}
	if !strings.Contains(verifyBody, "CauseDBUnreachable") {
		t.Error("the db.migration read error must classify as CauseDBUnreachable — a bounded-read timeout and a connection-refusal are ONE class at the classifier")
	}

	// (3) ONE shared constant — no scattered classify-path timeout literals.
	if !strings.Contains(source, "recoveryReadTimeout") {
		t.Error("the classify-path reads must share the recoveryReadTimeout constant, not scattered literals")
	}
}

// TestCommitNotFetchedDispatch_Retired pins STATBUS-071 (architect ruling
// 2026-07-15): the CauseCommitNotFetched DISPATCH arm is deleted from the resuming
// classify-then-act because the cause is structurally unreachable there (three
// invariants — the caller, the pre-swap-fetch phase invariant, and the recovery-
// boot checkout gate). This is the "the two things that remain real" surviving
// oracle's HALF-TWO: the classifier still NAMES the cause (proven behaviourally by
// TestVerifyBinaryObservedState_TargetMissingFromCloneIsUnknown in observed_state_test.go),
// and — pinned here — with no dispatch arm the cause falls to the DEFAULT human-stop
// WITH THE CAUSE NAMED (loud, actionable, zero retry of a structurally-impossible
// state). If a future refactor breaks an invariant, the box stops and says why.
func TestCommitNotFetchedDispatch_Retired(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) recoverFromFlag(")

	// No CauseCommitNotFetched dispatch arm survives — the retirement holds.
	if strings.Contains(body, "case CauseCommitNotFetched:") {
		t.Error("recoverFromFlag still has a `case CauseCommitNotFetched:` dispatch arm — the retired arm must stay deleted (STATBUS-071); the cause is structurally unreachable and must fall to the default human-stop")
	}
	// The surviving live arm proves the switch was surgically trimmed, not gutted.
	if !strings.Contains(body, "case CauseDBUnreachable:") {
		t.Error("recoverFromFlag lost the CauseDBUnreachable dispatch arm — only the commit-not-fetched arm was to be deleted")
	}
	// The default human-stop must NAME the cause (cause=%s) and refuse to guess —
	// so a retired/unrecognized cause reaching here is loud + actionable, never a
	// silent retry of an unknown.
	if !strings.Contains(body, "cause=%s") || !strings.Contains(body, "refusing to guess") {
		t.Error("the default arm must human-stop naming the cause (a cause= token plus 'refusing to guess') — a retired/unrecognized cause must be loud + actionable")
	}
}

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
	// commitNotFetchedSpec was deleted (STATBUS-071, dead dispatch arm); its
	// fetch machinery's watchdog constraint is guarded by the fetchStallTimeout
	// assertion below (fetchWithStallDetection lives on the forward-fetch path).
	for _, spec := range []retrySpec{d.dbUnreachableSpec()} {
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
