package upgrade

import (
	"strings"
	"testing"
)

// STATBUS-317 TRAP #2, structurally pinned. The empirical proof lives in
// test/sql/128_statbus_317_upgrade_actor_attribution.sql (the GUC must
// actually LAND, not merely exist as a code path) — these guard the SHAPE
// that makes that proof possible: the actor GUC and the write it is meant
// to attribute must share one transaction, at every call site, by
// construction, not by a future author remembering to wrap them.

// TestWithActorTxSetsGUCBeforeWriteInOneTransaction_STATBUS317 pins
// withActorTx itself: Begin, then (if operator is non-empty) set_config,
// then fn, then Commit — all inside the SAME pgx.Tx. A future edit that
// moved the set_config call to a separate d.queryConn.Exec (autocommit)
// would defeat the whole point silently.
func TestWithActorTxSetsGUCBeforeWriteInOneTransaction_STATBUS317(t *testing.T) {
	src := string(packageGoSources(t)["actor.go"])
	body := extractFuncBody(t, src, "func (d *Service) withActorTx(")

	beginIdx := strings.Index(body, "d.queryConn.Begin(ctx)")
	setIdx := strings.Index(body, "tx.Exec(ctx, \"SELECT set_config(")
	fnIdx := strings.Index(body, "fn(ctx, tx)")
	commitIdx := strings.Index(body, "tx.Commit(ctx)")

	if beginIdx < 0 || setIdx < 0 || fnIdx < 0 || commitIdx < 0 {
		t.Fatalf("withActorTx is missing one of Begin/set_config/fn/Commit — test is stale or the trap guard regressed (begin=%d set=%d fn=%d commit=%d)",
			beginIdx, setIdx, fnIdx, commitIdx)
	}
	if beginIdx >= setIdx || setIdx >= fnIdx || fnIdx >= commitIdx {
		t.Errorf(`withActorTx's operations are out of order: Begin(%d) < set_config(%d) < fn(%d) < Commit(%d) must all hold.

If set_config ever moves to run on the bare connection (before Begin, or
after Commit), it runs in its own autocommit transaction and evaporates
before the write — every row would silently record 'absent'. This must be
structurally impossible, not merely tested for once.`, beginIdx, setIdx, fnIdx, commitIdx)
	}
	// The write must go through tx, never d.queryConn directly — a caller
	// that used d.queryConn inside fn would silently escape this transaction.
	if strings.Contains(body[fnIdx:], "d.queryConn.Exec") {
		t.Error("withActorTx's own body must never call d.queryConn.Exec after invoking fn — the whole point is that fn's caller passes tx, not the bare connection")
	}
}

// TestScheduleStepWritesThroughActorTx_STATBUS317: the UPDATE that
// transitions public.upgrade to 'scheduled' must run inside withActorTx,
// via the tx it hands the closure — never a bare d.queryConn.Exec, which
// would be a second, unguarded write path that silently regresses to
// always recording 'absent'.
func TestScheduleStepWritesThroughActorTx_STATBUS317(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) scheduleStep(")

	if !strings.Contains(body, "d.withActorTx(ctx, operator,") {
		t.Fatal("scheduleStep must call d.withActorTx(ctx, operator, ...) — the actor-recording contract for this write path")
	}
	if !strings.Contains(body, "tx.Exec(ctx,") {
		t.Error("scheduleStep's UPDATE must run via tx.Exec (the transaction withActorTx opened), not the bare connection")
	}
}

// TestRunDismissWritesThroughActorTx_STATBUS317: same contract for dismiss.
func TestRunDismissWritesThroughActorTx_STATBUS317(t *testing.T) {
	src := readUpgradeServiceSource(t)
	body := extractFuncBody(t, src, "func (d *Service) RunDismiss(")

	if !strings.Contains(body, "d.withActorTx(ctx, operator,") {
		t.Fatal("RunDismiss must call d.withActorTx(ctx, operator, ...) — the actor-recording contract for this write path")
	}
	if !strings.Contains(body, "tx.Exec(ctx,") {
		t.Error("RunDismiss's UPDATE must run via tx.Exec (the transaction withActorTx opened), not the bare connection")
	}
}

// TestRunApplyThreadsOperatorToScheduleStep_STATBUS317: apply must share
// scheduleStep's actor-recording behavior, not reimplement or drop it —
// same "compose, don't reimplement" property STATBUS-258 already pins for
// register/schedule.
func TestRunApplyThreadsOperatorToScheduleStep_STATBUS317(t *testing.T) {
	body := extractFuncBody(t, readUpgradeApplySource(t), "func (d *Service) RunApply(")
	if !strings.Contains(body, "d.scheduleStep(ctx, input, recreate, operator)") {
		t.Error("RunApply must pass its own operator parameter through to scheduleStep — dropping it here would silently make every apply-recorded transition 'absent' regardless of what the caller resolved")
	}
}
