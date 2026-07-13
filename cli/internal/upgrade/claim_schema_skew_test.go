package upgrade

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-077 — SINGLE-SOURCE recovery guard (King's ruling: ONE source of truth).
//
// THE BUG it closes (FLAG-ABSENT class, install-recovery run 27683157288):
// the scheduled-upgrade claim wrote public.upgrade.from_commit_sha, but that
// column is added by migration 20260616104500 which runs in the upgrade's OWN
// migrate phase — AFTER the claim. Upgrading from a pre-20260616104500 schema
// (v2026.05.2) raised 42703 (undefined_column) and aborted the upgrade before
// writeUpgradeFlag + migrate (flag absent; db.migration baseline). Broke the real
// v2026.05.2 -> HEAD path. Confirmed in 4 scenarios (identical 42703).
//
// THE FIX (King's ruling, supersedes the earlier skew-tolerance option A):
// REMOVE from_commit_sha (STATBUS-062) ENTIRELY — the source commit was stored
// twice (the pinned `pre-upgrade` BRANCH and this column), a redundancy. The
// BRANCH becomes the single recovery source of truth; from_commit_VERSION stays
// as the display record. In service.go: the two claim sites stop writing
// from_commit_sha (keep from_commit_version); recoveryRollback + resumeNewSb +
// the in-process rollback stop reading it and resolve the restore target solely
// from the branch (restoreTargetSHA="" -> restoreGitStateFn's pre-upgrade-branch
// fallback, now unconditional); the release-back UPDATE drops from_commit_sha=NULL;
// sourceCommitSHA()/nullableCommitSHA() become dead and are removed. The SCHEMA is
// removed by DELETING migration 20260616104500 — verified 2026-06-17 NOT applied
// on any deployed box (dev/demo/rune: unrecorded + column absent), so a clean
// pre-release break (not a forward DROP migration). This keeps STATBUS-061's
// branch-grounded recovery (never d.version) and removes only STATBUS-062's column.
//
// WHY A SOURCE-STRUCTURE GUARD: the package does not unit-test live-DB claim/
// recovery paths (they are skipped — ground_truth_test.go:275) and the
// no-manual-DB-writes rule forbids DROP COLUMN on the dev DB. The idiom is to read
// service.go and assert structure (ground_truth_test.go:333). The BEHAVIORAL
// oracle is the install-recovery re-run — the 4 transitional flag-absent scenarios
// + the 2-preswap rollbacks certify single-source recovery.
//
// RED today (the from_commit_sha SQL uses are present) -> GREEN after the removal.
func TestUpgrade_FromCommitSHARemoved_SingleSourceRecovery_STATBUS077(t *testing.T) {
	source, err := os.ReadFile("service.go")
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	src := string(source)

	// (1) The from_commit_sha COLUMN must be GONE from all SQL in the upgrade
	//     service — no claim write, no recovery SELECT, no release-back NULL. We
	//     assert the SQL USES are gone (unambiguous fragments that cannot appear in
	//     prose), NOT the bare literal — so history/explanatory comments may still
	//     NAME from_commit_sha for searchability ("the from_commit_sha column,
	//     removed in STATBUS-077"); only its USE is forbidden. Single source of
	//     truth = the pinned pre-upgrade branch.
	sqlUses := []string{
		"from_commit_sha = $",    // claim write (parametrized): ExecuteUpgradeInline + executeScheduled
		"SELECT from_commit_sha", // recovery reads: recoveryRollback + resumeNewSb
		"from_commit_sha = NULL", // release-back UPDATE
	}
	for _, frag := range sqlUses {
		if strings.Contains(src, frag) {
			t.Errorf("STATBUS-077: service.go still USES the from_commit_sha column in SQL (%q) — remove "+
				"it; the single recovery source of truth is the pinned pre-upgrade branch (restoreTargetSHA=\"\" "+
				"-> restoreGitStateFn pre-upgrade fallback). Comments may still name the column.", frag)
		}
	}

	// (2) from_commit_version (the display record, migration 20260424160235) MUST
	//     survive — the claim still records the human-readable source version.
	if !strings.Contains(src, "from_commit_version") {
		t.Errorf("STATBUS-077: from_commit_version vanished from service.go — it is the display record " +
			"(distinct from the removed from_commit_sha) and MUST still be written at the claim.")
	}
}
