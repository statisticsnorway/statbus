package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestClassifyScheduleResult pins the complete result vocabulary owned by
// public.upgrade_schedule. Unknown database output fails loudly instead of
// silently falling into a caller branch.
func TestClassifyScheduleResult(t *testing.T) {
	cases := []struct {
		raw  string
		want scheduleResult
	}{
		{"scheduled", scheduleResultScheduled},
		{"superseded", scheduleResultSuperseded},
		{"already_scheduled", scheduleResultAlreadyScheduled},
		{"in_progress", scheduleResultInProgress},
		{"restore_reattempt_required", scheduleResultRestoreReattemptRequired},
		{"unregistered", scheduleResultUnregistered},
	}
	for _, c := range cases {
		t.Run(c.raw, func(t *testing.T) {
			got, err := classifyScheduleResult(c.raw)
			if err != nil {
				t.Fatalf("classifyScheduleResult(%q): %v", c.raw, err)
			}
			if got != c.want {
				t.Errorf("classifyScheduleResult(%q) = %q, want %q", c.raw, got, c.want)
			}
		})
	}

	if _, err := classifyScheduleResult("future_result"); err == nil {
		t.Fatal("classifyScheduleResult accepted an unknown database result")
	}
}

// TestErrNotRegistered_Actionable proves AC#3: scheduling an unregistered
// target yields an ACTIONABLE error that names the fix (`./sb upgrade register
// <target>`) and echoes the operator's input — not a silent insert.
func TestErrNotRegistered_Actionable(t *testing.T) {
	err := errNotRegistered("v2026.03.1", "abc1234f")
	if err == nil {
		t.Fatal("errNotRegistered returned nil — expected an actionable error")
	}
	msg := err.Error()
	for _, want := range []string{"not registered", "./sb upgrade register", "abc1234f"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error %q is missing the actionable fragment %q", msg, want)
		}
	}
}

// TestOnScheduledNotify_NoRawInsert is the STRONGER form of the old AC#9 guard,
// updated for STATBUS-183: the NOTIFY upgrade_apply handler MAY now create a
// candidate row (the apply-race fix), but ONLY through the guarded register path
// (registerTarget → upsertCandidate, which carries the STATBUS-169 tag↔commit
// write-guard) — NEVER a raw insert-if-missing inline in the handler. The
// surviving-and-stronger invariant: no candidate row is created except via the
// guarded path. A future edit that inlined a raw INSERT would revive the
// fabricate-a-row-from-a-NOTIFY path 086 forbade.
func TestOnScheduledNotify_NoRawInsert(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) onScheduledNotify(")
	if strings.Contains(body, "INSERT INTO public.upgrade") {
		t.Error("onScheduledNotify must NOT raw-INSERT — a candidate row is created only via the guarded registerTarget/upsertCandidate path (STATBUS-086/183)")
	}
	if !strings.Contains(body, "registerTarget") {
		t.Error("onScheduledNotify's unregistered branch must register via registerTarget (the guarded path), not drop the apply (STATBUS-183 piece 1)")
	}
	if !strings.Contains(body, "promoteExistingCandidate") {
		t.Error("onScheduledNotify must promote via promoteExistingCandidate (STATBUS-183)")
	}
}

// TestScheduleDoorsUseDatabaseFunction_STATBUS333 proves both Go scheduling
// doors call the one database function and contain no raw schedule reset.
func TestScheduleDoorsUseDatabaseFunction_STATBUS333(t *testing.T) {
	for _, subject := range []struct {
		name string
		sig  string
	}{
		{"service-notify", "func (d *Service) promoteExistingCandidate("},
		{"cli", "func (d *Service) scheduleStep("},
	} {
		t.Run(subject.name, func(t *testing.T) {
			body := funcBody(t, "service.go", subject.sig)
			if strings.Contains(body, "UPDATE public.upgrade") {
				t.Error("schedule door must not raw-UPDATE public.upgrade; public.upgrade_schedule owns the reset")
			}
			if !strings.Contains(body, "public.upgrade_schedule") {
				t.Error("schedule door must call public.upgrade_schedule")
			}
		})
	}
}

// TestRunSchedule_CommitAuthoritative_FailLoud_STATBUS169 keeps the existing
// commit-authoritative and actionable-unregistered guarantees after the reset
// moved into SQL.
func TestRunSchedule_CommitAuthoritative_FailLoud_STATBUS169(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) scheduleStep(")
	if !strings.Contains(funcBody(t, "service.go", "func (d *Service) RunSchedule("), "scheduleStep(") {
		t.Fatal("RunSchedule must delegate to scheduleStep — if that link is gone this guard is reading a function nothing calls")
	}
	if !strings.Contains(body, "string(sha), recreate") {
		t.Error("scheduleStep must call the database function with the resolved canonical commit SHA")
	}
	if strings.Contains(body, "ANY(commit_tags)") {
		t.Error("the scheduling path must NOT select rows by commit_tags — a tag is never the row selector (STATBUS-169 AC#2)")
	}
	if !strings.Contains(body, "errNotRegistered") {
		t.Error("the database function's unregistered result must return actionable errNotRegistered (STATBUS-169 AC#3)")
	}
}

// TestKeepTagForRow_STATBUS169 pins the pruner's cache-reconciliation rule: a tag
// on a row survives ONLY if git still has it AND it still points at that row's
// commit. Deleted (absent) and MOVED (points elsewhere) both drop.
func TestKeepTagForRow_STATBUS169(t *testing.T) {
	rowSHA := CommitSHA("143cece86aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	elsewhere := CommitSHA("a1b58193daaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	tag := "v2026.07.0-rc.01"
	cases := []struct {
		name string
		git  map[string]CommitSHA
		want bool
	}{
		{"points at the row's commit → keep", map[string]CommitSHA{tag: rowSHA}, true},
		{"moved (git points it elsewhere) → drop", map[string]CommitSHA{tag: elsewhere}, false},
		{"deleted (absent from git) → drop", map[string]CommitSHA{}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := keepTagForRow(tag, c.git, rowSHA); got != c.want {
				t.Errorf("keepTagForRow = %v, want %v", got, c.want)
			}
		})
	}
}

// TestUpsertCandidate_WriteGuard_STATBUS169 pins AC#1: the register write refuses
// to record a tag that git does not point at the target commit — a false cache
// fact never gets written fresh.
func TestUpsertCandidate_WriteGuard_STATBUS169(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) upsertCandidate(")
	if !strings.Contains(body, "RevParse") {
		t.Error("upsertCandidate must rev-parse the tag to verify it points at the commit BEFORE writing (STATBUS-169 AC#1)")
	}
	if !strings.Contains(body, "refusing to register") {
		t.Error("upsertCandidate must LOUDLY refuse to record a tag that does not point at the row's commit (STATBUS-169 AC#1)")
	}
}

// TestPruneDeletedTags_DropsMovedTags_STATBUS169 pins the pruner extension: it
// checks tag→commit POINTING (via keepTagForRow + the row's commit_sha), not tag
// existence alone, and drops+logs MOVED tags.
func TestPruneDeletedTags_DropsMovedTags_STATBUS169(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) pruneDeletedTags(")
	if !strings.Contains(body, "keepTagForRow") {
		t.Error("pruneDeletedTags must decide via keepTagForRow (existence AND pointing), not existence alone (STATBUS-169)")
	}
	if !strings.Contains(body, "MOVED") {
		t.Error("pruneDeletedTags must drop + log MOVED tags, not only DELETED ones (STATBUS-169)")
	}
	if !strings.Contains(body, "commit_sha, commit_tags") {
		t.Error("pruneDeletedTags must SELECT commit_sha to check tag→commit pointing (STATBUS-169)")
	}
}

// TestPruneDeletedTags_EmptyKeptIsNeverNull pins the encoding defect found live
// on dev (2026-09-03): when EVERY tag on a row is pruned, `kept` must be an
// empty, non-nil slice. pgx encodes a nil []string as SQL NULL, and
// public.upgrade.commit_tags is NOT NULL, so the UPDATE was rejected on every
// discovery tick; the swallowed error hid it while the journal repeated the same
// "Pruned ..." lines every 5 minutes (25 rows, 744 identical lines in 48h). The
// write error must also be logged, never discarded.
func TestPruneDeletedTags_EmptyKeptIsNeverNull(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) pruneDeletedTags(")
	if strings.Contains(body, "var kept []string") {
		t.Error("pruneDeletedTags declares `kept` as a nil slice; an all-pruned row then writes SQL NULL into NOT NULL commit_tags")
	}
	if !strings.Contains(body, "kept := make([]string, 0, len(p.tags))") {
		t.Error("pruneDeletedTags must build `kept` as an empty non-nil slice so an all-pruned row writes '{}' not NULL")
	}
	if strings.Contains(body, "_, _ = d.queryConn.Exec(ctx,") {
		t.Error("pruneDeletedTags discards the reconcile UPDATE error; a constraint rejection must be logged, not hidden")
	}
	if !strings.Contains(body, "tag reconcile did not land") {
		t.Error("pruneDeletedTags must log a failed reconcile UPDATE with the row id and intended values")
	}
}

// funcBody returns the source text of the function whose signature prefix is
// `sig`, from `file`, up to (not including) the next top-level `func ` after it.
// Mirrors the source-inspection guards already used in this package
// (rollback_terminal_write_test.go).
func funcBody(t *testing.T, file, sig string) string {
	t.Helper()
	src, err := os.ReadFile(file)
	if err != nil {
		t.Fatalf("read %s: %v", file, err)
	}
	s := string(src)
	start := strings.Index(s, sig)
	if start < 0 {
		t.Fatalf("signature %q not found in %s", sig, file)
	}
	rest := s[start+len(sig):]
	if end := strings.Index(rest, "\nfunc "); end >= 0 {
		return rest[:end]
	}
	return rest
}
