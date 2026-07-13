package upgrade

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-092 — the --recreate intent must be DURABLE on the public.upgrade row,
// not carried in a volatile in-memory flag set by a racing ':recreate' NOTIFY.
//
// THE BUG it closes: RunSchedule sent an out-of-band `NOTIFY upgrade_apply
// '<sha>:recreate'` AFTER the scheduling UPDATE had already fired the trigger's
// sha-NOTIFY. The daemon processed the sha-NOTIFY first and, in the same select
// iteration, ran executeScheduled → claim → executeUpgrade → writeUpgradeFlag
// with d.pendingRecreate still FALSE, before the ':recreate' NOTIFY was ever
// dequeued. So a --recreate upgrade silently ran as a normal (data-preserving)
// one — the operator asked for a recreate and didn't get one.
//
// THE FIX: a durable `recreate boolean` column on public.upgrade, set at every
// promote-to-scheduled and read ATOMICALLY at claim (RETURNING recreate), carried
// through executeUpgrade → writeUpgradeFlag → flag.Recreate → applyNewSbUpgrading. The
// volatile d.pendingRecreate field and the ':recreate' NOTIFY protocol are removed.
//
// WHY A SOURCE-STRUCTURE GUARD (not a live-DB unit test): this package does not
// unit-test live-DB claim/recovery paths — they are skipped, and the
// no-manual-DB-writes rule applies (see claim_schema_skew_test.go). The idiom is
// to assert service.go structure; the BEHAVIORAL oracle is exercising a real
// `./sb upgrade schedule --recreate` on the dev stack and observing the flag carry
// the intent (done at build time), plus the install-recovery re-run.
func TestRecreateIntentIsDurableOnRow_STATBUS092(t *testing.T) {
	source, err := os.ReadFile("service.go")
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	src := string(source)

	// (1) The volatile in-memory flag is GONE — recreate no longer rides a field
	//     mutated by a racing NOTIFY. (Comments may still NAME the historical flag
	//     for searchability; the qualified USE `d.pendingRecreate` must be absent.)
	if strings.Contains(src, "d.pendingRecreate") {
		t.Errorf("STATBUS-092: service.go still uses d.pendingRecreate — recreate must be durable on " +
			"public.upgrade.recreate, read at claim; the volatile flag raced the ':recreate' NOTIFY.")
	}

	// (2) The out-of-band ':recreate' NOTIFY payload is no longer BUILT — the racy
	//     signal is gone. (A defensive `TrimSuffix(payload, ":recreate")` that
	//     strips+IGNORES a legacy suffix may remain; only CONSTRUCTING the payload
	//     via concatenation is forbidden.)
	if strings.Contains(src, `+ ":recreate"`) {
		t.Errorf("STATBUS-092: service.go still BUILDS a ':recreate' NOTIFY payload — the racy out-of-band " +
			"recreate signal must be removed; intent is durable on the row.")
	}

	// (3) The durable intent is READ ATOMICALLY at claim via RETURNING, so it can
	//     never be lost to NOTIFY timing. STATBUS-159 consolidated the two former
	//     byte-identical claim sites into ONE shared helper (claimScheduledUpgrade)
	//     whose claim RETURNs the superset (commit_tags, recreate); BOTH former sites
	//     (executeScheduled + ExecuteUpgradeInline) now route through it, so both the
	//     scheduled and install-inline paths read recreate durably at claim.
	if !strings.Contains(src, "RETURNING commit_tags, recreate") {
		t.Errorf("STATBUS-092/159: the shared claim helper must read the durable column via " +
			"RETURNING commit_tags, recreate.")
	}
	if strings.Count(src, "d.claimScheduledUpgrade(ctx, id)") < 2 {
		t.Errorf("STATBUS-159: both claim sites (executeScheduled + ExecuteUpgradeInline) must route " +
			"through the shared claimScheduledUpgrade helper so recreate is read durably at claim in both paths.")
	}

	// (4) The intent is SET durably at schedule time (RunSchedule's promote UPDATE),
	//     and set explicitly (false) on a NOTIFY-driven promote so it never carries
	//     a stale true.
	if !strings.Contains(src, "recreate = $2") {
		t.Errorf("STATBUS-092: RunSchedule must persist the --recreate flag on the row (recreate = $2).")
	}
	if !strings.Contains(src, "recreate = false") {
		t.Errorf("STATBUS-092: onScheduledNotify must set recreate = false on a NOTIFY-driven promote " +
			"(no stale-true carryover; a plain NOTIFY carries no recreate intent).")
	}

	// (5) executeUpgrade carries the claim-read recreate through to the flag, NOT a
	//     volatile field: writeUpgradeFlag(..., trigger, recreate).
	if !strings.Contains(src, "trigger, recreate)") {
		t.Errorf("STATBUS-092: executeUpgrade must pass the claim-read recreate to writeUpgradeFlag so it " +
			"flows durably to flag.Recreate → applyNewSbUpgrading.")
	}
}
