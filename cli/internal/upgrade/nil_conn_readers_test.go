package upgrade

// STATBUS-428: after a recovery path that could not reconnect, d.queryConn and
// d.listenConn are nil. pgx v5 dereferences a nil *Conn receiver, so every
// daemon reader reachable in that state must fail with the named
// ErrQueryConnUnavailable / ErrListenConnUnavailable (or its established
// degraded fallback) instead of panicking.

import (
	"context"
	"errors"
	"testing"
)

// The accessors are the ONE guard: nil fields yield the named errors.
func TestNilConnAccessors(t *testing.T) {
	d := &Service{}
	if _, err := d.queryConnOrErr("test"); !errors.Is(err, ErrQueryConnUnavailable) {
		t.Errorf("queryConnOrErr: got %v, want errors.Is(err, ErrQueryConnUnavailable)", err)
	}
	if _, err := d.listenConnOrErr("test"); !errors.Is(err, ErrListenConnUnavailable) {
		t.Errorf("listenConnOrErr: got %v, want errors.Is(err, ErrListenConnUnavailable)", err)
	}
}

// Every error-returning reader must surface ErrQueryConnUnavailable.
func TestNilConnQueryReadersReturnNamedError(t *testing.T) {
	ctx := context.Background()
	d := &Service{}
	check := func(name string, err error) {
		t.Helper()
		if !errors.Is(err, ErrQueryConnUnavailable) {
			t.Errorf("%s: got error %v, want errors.Is(err, ErrQueryConnUnavailable)", name, err)
		}
	}

	check("ExecuteUpgradeInline", d.ExecuteUpgradeInline(ctx, 1, "abc123", ""))
	check("acquireAdvisoryLock", d.acquireAdvisoryLock(ctx))
	check("resumeNewSb", d.resumeNewSb(ctx, UpgradeFlag{}))
	check("ReattemptRestore", d.ReattemptRestore(ctx, 1))
	check("recoverServingTreeConvergence", d.recoverServingTreeConvergence(ctx, 1, nil))
	check("executeUpgrade", d.executeUpgrade(ctx, upgradeClaimSnapshot{}, "v2026.01.1", nil, "test", "test", false))

	if _, err := d.upsertCandidate(ctx, CommitSHA("abc123"), candidateMeta{}); true {
		check("upsertCandidate", err)
	}
	if _, err := d.promoteExistingCandidate(ctx, CommitSHA("abc123")); true {
		check("promoteExistingCandidate", err)
	}
	if _, err := d.claimScheduledUpgradePass(ctx, 1); true {
		check("claimScheduledUpgradePass", err)
	}
	if _, err := d.CommitSHAsByTag(ctx, ReleaseTag("v2026.01.1")); true {
		check("CommitSHAsByTag", err)
	}
	if _, err := d.TagsAtCommit(ctx, CommitSHA("abc123")); true {
		check("TagsAtCommit", err)
	}
	if _, _, err := d.servingTreeConvergenceObligation(ctx, 1); true {
		check("servingTreeConvergenceObligation", err)
	}
	if _, err := d.incrementRecoveryAttempts(ctx, 1); true {
		check("incrementRecoveryAttempts", err)
	}
	if _, _, err := d.UnparkByID(ctx, 1); true {
		check("UnparkByID", err)
	}
	if _, err := d.finalizePendingRollback(ctx, 1, "test"); true {
		check("finalizePendingRollback", err)
	}
	if _, err := d.isRollbackFinishPending(ctx, 1); true {
		check("isRollbackFinishPending", err)
	}
}

// A nil query session is a database-unreachable state at the observed-state
// classifier: the recovery backoff must see CauseDBUnreachable, not a panic.
func TestNilConnVerifyObservedStateClassifiesUnreachable(t *testing.T) {
	d := &Service{}
	obs, cause, _ := d.verifyUpgradeObservedStateEx(context.Background(), "abc123")
	if obs != ObservedPositionUnreadable || cause != CauseDBUnreachable {
		t.Errorf("verifyUpgradeObservedStateEx with nil queryConn = (%v, %v), want (ObservedPositionUnreadable, CauseDBUnreachable)", obs, cause)
	}
}

// String-only readers keep their established degraded fallbacks.
func TestNilConnStringReadersDegrade(t *testing.T) {
	ctx := context.Background()
	d := &Service{}
	if got := d.loadLogRelPath(ctx, 1); got != "" {
		t.Errorf("loadLogRelPath with nil queryConn = %q, want the established empty fallback", got)
	}
	state, img := d.probeRowStateForDiagnostic(ctx, 1)
	if state != "<unreadable>" || img != "<unreadable>" {
		t.Errorf("probeRowStateForDiagnostic with nil queryConn = (%q, %q), want the established <unreadable> pair", state, img)
	}
}

// Best-effort void sweeps skip their pass; returning at all (no panic) is the
// assertion — a nil dereference crashes the test binary.
func TestNilConnVoidReadersReturn(t *testing.T) {
	ctx := context.Background()
	d := &Service{}
	d.markImagesFailed(ctx, 1, "abc123def456", "reason")
	d.verifyArtifacts(ctx)
	d.syncConfigToSystemInfo(ctx)
	d.supersedeOlderReleases(ctx, "abc123")
	d.supersedeCompletedPrereleases(ctx, "abc123")
	d.cleanStaleMaintenance(ctx)
	d.clearStaleReadOnlyWindow(ctx)
	d.checkMissedUpgrades(ctx)
	d.pruneDeletedTags(ctx, nil)
	d.preDownloadImages(ctx)
	d.supersedeBelowInstalled(ctx)
	d.recordApplyRefused(ctx, "input", "reason")
	d.clearApplyRefused(ctx)
}
