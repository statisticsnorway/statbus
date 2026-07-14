package upgrade

import (
	"strings"
	"testing"
)

// STATBUS-183 apply-notify-race oracle (source-shape guards, the idiom this
// package uses for the daemon's DB-touching handlers — see
// schedule_require_register_test.go). The BEHAVIORAL proof (a poke sent within
// seconds of a fresh cut converging row-completed) is the next RC's deploy run
// (AC#3); these lock the four ruled pieces structurally so a regression reddens
// the pure lane immediately.

// Piece 2: the handler makes the target local with ONE fetch BEFORE resolving, so
// an apply that beats the box's own fetch of a freshly-cut release still resolves.
func TestApplyRace_FetchLegBeforeResolve(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) onScheduledNotify(")
	fetchIdx := strings.Index(body, "ensureCommitLocal")
	resolveIdx := strings.Index(body, "resolveUpgradeTarget")
	if fetchIdx < 0 {
		t.Fatal("onScheduledNotify must attempt ensureCommitLocal before resolving (STATBUS-183 piece 2)")
	}
	if resolveIdx < 0 {
		t.Fatal("onScheduledNotify must call resolveUpgradeTarget")
	}
	if fetchIdx > resolveIdx {
		t.Error("the ensureCommitLocal fetch leg must run BEFORE resolveUpgradeTarget (STATBUS-183 piece 2) so a NOTIFY that beats the box's own fetch can still resolve")
	}
}

// A2 (STATBUS-183 comment #3): the tag fetch MUST use the explicit refs/tags
// refspec form. Plain `git fetch origin <tag>` lands the commit in FETCH_HEAD only
// and does NOT create the local tag ref, so `git rev-parse <tag>` still fails —
// the exact rc.06 case the order-only fetch-before-resolve assert missed. This
// closes that class: a full SHA fetches by the sha form, anything else (a tag) by
// the refspec form that writes refs/tags/<ref> locally.
func TestApplyRace_TagFetchUsesRefsTagsRefspec(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) ensureCommitLocal(")
	if !strings.Contains(body, "isCommitSHAShape") {
		t.Error("ensureCommitLocal must class-branch on isCommitSHAShape (full SHA vs tag) — STATBUS-183 A1")
	}
	if !strings.Contains(body, `"refs/tags/" + ref + ":refs/tags/" + ref`) {
		t.Error("ensureCommitLocal must fetch a tag via the explicit refs/tags refspec form (plain `git fetch origin <tag>` leaves the tag ref absent → rev-parse fails, the rc.06 case) — STATBUS-183 A1/A2")
	}
}

// Piece 1: the unregistered branch registers through the guarded path then re-runs
// the promote — no longer a silent drop.
func TestApplyRace_UnregisteredRegistersThenPromotes(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) onScheduledNotify(")
	uIdx := strings.Index(body, "scheduleResultUnregistered")
	if uIdx < 0 {
		t.Fatal("onScheduledNotify must still handle scheduleResultUnregistered")
	}
	branch := body[uIdx:]
	if !strings.Contains(branch, "registerTarget") {
		t.Error("the unregistered branch must register via registerTarget, not drop the apply (STATBUS-183 piece 1)")
	}
	if !strings.Contains(branch, "promoteExistingCandidate") {
		t.Error("the unregistered branch must RE-RUN promoteExistingCandidate after registering (STATBUS-183 piece 1)")
	}
	// The old silent-drop message must be gone.
	if strings.Contains(body, "UNREGISTERED commit") {
		t.Error("onScheduledNotify must no longer print the silent-drop 'UNREGISTERED commit … ignored' message (STATBUS-183)")
	}
}

// Piece 1 (guard): registration goes through upsertCandidate, which carries the
// STATBUS-169 tag↔commit write-guard internally (tested by
// TestUpsertCandidate_WriteGuard_STATBUS169). So no row is created ungated.
func TestApplyRace_RegisterTargetGoesThroughGuardedUpsert(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) registerTarget(")
	if !strings.Contains(body, "upsertCandidate") {
		t.Error("registerTarget must create the row via upsertCandidate — the single guarded register path (STATBUS-169/183)")
	}
	if strings.Contains(body, "INSERT INTO public.upgrade") {
		t.Error("registerTarget must NOT raw-INSERT — it must delegate to upsertCandidate so the 169 write-guard cannot be bypassed")
	}
}

// Piece 3: EVERY refuse path is durable (writes the system_info signal 170 phase-2
// + the admin UI read), not just a stdout line. There are ≥2 refuse paths
// (unresolvable-after-fetch and register-refused), so require recordApplyRefused
// on more than one.
func TestApplyRace_EveryRefusePathIsDurable(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) onScheduledNotify(")
	if n := strings.Count(body, "recordApplyRefused"); n < 2 {
		t.Errorf("onScheduledNotify must write a durable refusal on EVERY refuse path (got %d recordApplyRefused calls, want ≥2: unresolvable-after-fetch + register-refused) — STATBUS-183 piece 3", n)
	}
	rec := funcBody(t, "service.go", "func (d *Service) recordApplyRefused(")
	if !strings.Contains(rec, "system_info") || !strings.Contains(rec, "upgrade_apply_refused") {
		t.Error("recordApplyRefused must persist system_info key 'upgrade_apply_refused' (STATBUS-183 piece 3)")
	}
	if !strings.Contains(rec, "jsonb_build_object") || !strings.Contains(rec, "occurred_at") {
		t.Error("recordApplyRefused must record {input, reason, occurred_at} as JSON (STATBUS-183 piece 3)")
	}
}

// Piece 3: the durable refusal is CLEARED on the next successful schedule, so a
// stale refusal never lingers once the version is actually scheduled.
func TestApplyRace_RefusalClearedOnSuccess(t *testing.T) {
	sched := funcBody(t, "service.go", "func (d *Service) onApplyScheduled(")
	if !strings.Contains(sched, "clearApplyRefused") {
		t.Error("onApplyScheduled (the successful-promote finisher) must clear the durable refusal (STATBUS-183 piece 3)")
	}
	clr := funcBody(t, "service.go", "func (d *Service) clearApplyRefused(")
	if !strings.Contains(clr, "DELETE FROM public.system_info") || !strings.Contains(clr, "upgrade_apply_refused") {
		t.Error("clearApplyRefused must DELETE the 'upgrade_apply_refused' system_info key (STATBUS-183 piece 3)")
	}
}

// Piece 4: race hygiene — upsertCandidate is idempotent on commit_sha (ON CONFLICT),
// so the incident's actual race (inline register vs the independent discovery
// registering the same tag moments later) is benign in BOTH orders: whichever runs
// second is an ON CONFLICT DO UPDATE on the same row, never a duplicate or an error.
func TestApplyRace_UpsertIdempotentOnCommitSha(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) upsertCandidate(")
	if strings.Count(body, "ON CONFLICT (commit_sha)") < 2 {
		t.Error("upsertCandidate must be idempotent via ON CONFLICT (commit_sha) on BOTH the tagged and untagged inserts — this is what makes the apply-vs-discovery race benign in both orders (STATBUS-183 piece 4)")
	}
}

// The promote UPDATE moved into promoteExistingCandidate (STATBUS-183) — it must
// keep the commit-authoritative, no-insert, fail-classified shape RunSchedule has.
func TestPromoteExistingCandidate_CommitAuthoritativeNoInsert(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) promoteExistingCandidate(")
	if !strings.Contains(body, "UPDATE public.upgrade") {
		t.Error("promoteExistingCandidate must promote via UPDATE public.upgrade")
	}
	if !strings.Contains(body, "WHERE commit_sha = $1") {
		t.Error("promoteExistingCandidate must select by commit (WHERE commit_sha = $1), never by tag (STATBUS-169 AC#2)")
	}
	if strings.Contains(body, "INSERT INTO public.upgrade") {
		t.Error("promoteExistingCandidate must NOT insert — it promotes an existing candidate only")
	}
	if !strings.Contains(body, "classifyScheduleResult") {
		t.Error("promoteExistingCandidate must classify the outcome (promoted / already-scheduled / unregistered) via classifyScheduleResult")
	}
}
