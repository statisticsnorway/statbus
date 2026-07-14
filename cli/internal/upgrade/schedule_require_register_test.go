package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestClassifyScheduleResult proves the require-register decision (STATBUS-086,
// AC#9): a promote-UPDATE that affects rows means the candidate was promoted; 0
// rows on an existing row is a benign already-scheduled no-op; 0 rows with NO
// row is Unregistered — which the caller turns into a loud no-op, NEVER an
// insert. This is the pure core of "schedule requires register, everywhere."
func TestClassifyScheduleResult(t *testing.T) {
	cases := []struct {
		name   string
		rows   int64
		exists bool
		want   scheduleResult
	}{
		{"promoted", 1, true, scheduleResultPromoted},
		{"promoted-regardless-of-exists-probe", 2, false, scheduleResultPromoted},
		{"already-scheduled-no-op", 0, true, scheduleResultAlreadyScheduled},
		{"unregistered-never-insert", 0, false, scheduleResultUnregistered},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := classifyScheduleResult(c.rows, c.exists); got != c.want {
				t.Errorf("classifyScheduleResult(%d, %v) = %v, want %v", c.rows, c.exists, got, c.want)
			}
		})
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

// TestRunSchedule_CommitAuthoritative_FailLoud_STATBUS169 pins the two
// STATBUS-169 properties on the scheduling UPDATE (already true on master via the
// STATBUS-086 refactor; this guards against regressing back toward rc.04):
//   - AC#2/B: the promote-UPDATE selects by COMMIT (`WHERE commit_sha = $1`),
//     NEVER by a tag (`ANY(commit_tags)`) — a tag can never match multiple rows.
//   - AC#3: a 0-row promote fails LOUDLY (RowsAffected()==0 → errNotRegistered /
//     the in-progress refusal), never a silent exit-0 success.
func TestRunSchedule_CommitAuthoritative_FailLoud_STATBUS169(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) RunSchedule(")
	if !strings.Contains(body, "WHERE commit_sha = $1") {
		t.Error("RunSchedule's scheduling UPDATE must select by `WHERE commit_sha = $1` (commit-authoritative, single row) — STATBUS-169 AC#2")
	}
	if strings.Contains(body, "ANY(commit_tags)") {
		t.Error("RunSchedule must NOT select rows by commit_tags — a tag is never the row selector (STATBUS-169 AC#2)")
	}
	if !strings.Contains(body, "RowsAffected() == 0") {
		t.Error("RunSchedule must check RowsAffected()==0 — a 0-row promote must fail loudly, never report success (STATBUS-169 AC#3)")
	}
	if !strings.Contains(body, "errNotRegistered") {
		t.Error("RunSchedule's 0-row path must return the actionable errNotRegistered (STATBUS-169 AC#3)")
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
