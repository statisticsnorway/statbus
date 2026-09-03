package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestClaimScheduledUpgradeChecksConfigRefusalMarkerFirst — STATBUS-307,
// the architect's follow-on ruling: block-by-absence (relying on the
// upgrade path merely needing a fresh config it cannot get) was rejected
// as a contract. The parked-policy state needs an EXPLICIT execution
// guard. claimScheduledUpgrade is the ONE function both dispatch paths
// share (ExecuteUpgradeInline for ./sb install's inline dispatch,
// executeScheduled for the daemon's own periodic pickup — see its own
// header comment, "Consolidates the two former claim sites"), so this
// pins the guard structurally at the one chokepoint that covers both.
//
// Cannot be exercised end-to-end without a live queryConn (the function
// opens a real transaction), so this is the same source-reading structural
// technique already established for the boot-time fork
// (TestRecoveryBootParksOnRefusalWithExistingConfig).
func TestClaimScheduledUpgradeChecksConfigRefusalMarkerFirst(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	fn := extractFuncBody(t, string(src), "func (d *Service) claimScheduledUpgrade(")

	guardIdx := strings.Index(fn, "ReadConfigRefusalMarker(d.projDir)")
	if guardIdx < 0 {
		t.Fatal("claimScheduledUpgrade must check ReadConfigRefusalMarker — test is stale or the STATBUS-307 guard regressed")
	}

	// FIRST ACT: the guard must precede every other read/mutation in the
	// function — in particular the standing-park read, which is the first
	// thing the function did before this guard existed.
	parkReadIdx := strings.Index(fn, `SELECT id, COALESCE(recovery_parked_reason, '')`)
	if parkReadIdx < 0 {
		t.Fatal("expected the standing-park SELECT to still be present — test is stale")
	}
	if guardIdx > parkReadIdx {
		t.Error("the config-refusal guard must run BEFORE the standing-park read — it is supposed to be this function's first act, not an afterthought bolted on later")
	}

	// FAILS CLOSED both ways: a confirmed marker refuses, AND a read ERROR
	// refuses too (STATBUS-039/111/159: unverified is not permission) —
	// neither branch may fall through to the claim.
	guardWindow := fn[guardIdx:parkReadIdx]
	if !strings.Contains(guardWindow, "merr != nil") {
		t.Error("a marker READ ERROR must also refuse (fail closed) — an unreadable marker is not evidence the box is fine")
	}
	if !strings.Contains(guardWindow, "marker != nil") {
		t.Error("a CONFIRMED marker must refuse — the positive case")
	}
	if strings.Count(guardWindow, "return scheduledUpgradeClaim{},") < 2 {
		t.Error("both the read-error and confirmed-marker branches must return a refusal (empty claim, err) — found fewer than 2 refusal returns in the guard")
	}
}

// TestClaimScheduledUpgradeGuard_NoMarkerFallsThrough confirms the common
// case (no marker at all — the box's policy is unambiguous) is NOT gated:
// the guard's own window must not unconditionally refuse.
func TestClaimScheduledUpgradeGuard_NoMarkerFallsThrough(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	fn := extractFuncBody(t, string(src), "func (d *Service) claimScheduledUpgrade(")

	condIdx := strings.Index(fn, "if marker, merr := ReadConfigRefusalMarker")
	if condIdx < 0 {
		t.Fatal("claimScheduledUpgrade must check ReadConfigRefusalMarker inside an `if marker, merr :=` conditional — test is stale or the STATBUS-307 guard regressed")
	}
	parkReadIdx := strings.Index(fn, `SELECT id, COALESCE(recovery_parked_reason, '')`)
	if parkReadIdx < 0 {
		t.Fatal("expected the standing-park SELECT to still be present — test is stale")
	}

	// The guard must be an if/else-if shape (both nil falls through past
	// it) — pinned structurally: the condition itself is `if marker, merr :=
	// ...; merr != nil` / `else if marker != nil`, so a future edit that
	// replaced it with an unconditional refusal would fail this exact
	// string match (there would be no `if ... :=` init-statement left to
	// find), and the standing-park read below would become unreachable
	// dead code — this test only needs to confirm the conditional form
	// survives.
	guardWindow := fn[condIdx:parkReadIdx]
	if !strings.Contains(guardWindow, "merr != nil") || !strings.Contains(guardWindow, "marker != nil") {
		t.Error("the guard must branch on BOTH merr != nil and marker != nil as distinct conditions — a bare, unconditional refusal here would block every upgrade dispatch, including on a perfectly healthy box")
	}
}
