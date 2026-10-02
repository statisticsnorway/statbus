package cmd

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-441: the inline scheduled-upgrade dispatch must migrate the schema
// BEFORE ExecuteUpgradeInline's claim, because the claim's SQL sets
// claim_token (migration 20260923202403) and a box whose schema predates that
// migration dies at the claim with SQLSTATE 42703 — with the pipeline's own
// Migrations step unreachable behind it. These tests pin the ordering and the
// abort semantics through the dispatch's seams, no schema fixture needed.
func withInlineDispatchSeams(t *testing.T) (calls *[]string) {
	t.Helper()
	record := []string{}
	calls = &record

	prevMigrate := inlineDispatchMigrateUp
	prevLoad := inlineDispatchLoadConfig
	prevExecute := inlineDispatchExecute
	t.Cleanup(func() {
		inlineDispatchMigrateUp = prevMigrate
		inlineDispatchLoadConfig = prevLoad
		inlineDispatchExecute = prevExecute
	})

	inlineDispatchLoadConfig = func(context.Context, *upgrade.Service) error {
		record = append(record, "load")
		return nil
	}
	inlineDispatchMigrateUp = func(string) error {
		record = append(record, "migrate")
		return nil
	}
	inlineDispatchExecute = func(context.Context, *upgrade.Service, int, string, string) error {
		record = append(record, "execute")
		return nil
	}
	return calls
}

func scheduledDetail() *install.Detail {
	return &install.Detail{
		ScheduledRowID:    42,
		TargetCommitSHA:   "bcb1d568efa201eb76bfe2f9d124f8a29c7dacf5",
		TargetDisplayName: "v2026.10.0-rc.11",
	}
}

func TestInlineDispatchMigratesBeforeClaim(t *testing.T) {
	calls := withInlineDispatchSeams(t)

	if err := runInlineUpgradeScheduled(t.TempDir(), scheduledDetail()); err != nil {
		t.Fatalf("dispatch with faked seams: %v", err)
	}
	got := strings.Join(*calls, ",")
	if got != "load,migrate,execute" {
		t.Fatalf("dispatch order = %q, want load,migrate,execute — the claim must never precede the schema catch-up (STATBUS-441's 42703)", got)
	}
}

func TestInlineDispatchMigrateFailureAbortsBeforeClaim(t *testing.T) {
	calls := withInlineDispatchSeams(t)
	inlineDispatchMigrateUp = func(string) error {
		*calls = append(*calls, "migrate")
		return errors.New("psql: connection refused")
	}

	err := runInlineUpgradeScheduled(t.TempDir(), scheduledDetail())
	if err == nil {
		t.Fatal("a failed pre-claim migration must abort the dispatch")
	}
	if !strings.Contains(err.Error(), "migrate the database schema before the scheduled upgrade claim") {
		t.Fatalf("abort lost its cause framing: %v", err)
	}
	if got := strings.Join(*calls, ","); got != "load,migrate" {
		t.Fatalf("calls = %q, want load,migrate — the claim must not fire after a failed schema catch-up", got)
	}
}

func TestInlineDispatchPassesTheScheduledRowThrough(t *testing.T) {
	_ = withInlineDispatchSeams(t)
	var gotID int
	var gotSHA, gotName string
	inlineDispatchExecute = func(_ context.Context, _ *upgrade.Service, id int, sha, name string) error {
		gotID, gotSHA, gotName = id, sha, name
		return nil
	}

	detail := scheduledDetail()
	if err := runInlineUpgradeScheduled(t.TempDir(), detail); err != nil {
		t.Fatalf("dispatch with faked seams: %v", err)
	}
	if gotID != int(detail.ScheduledRowID) || gotSHA != detail.TargetCommitSHA || gotName != detail.TargetDisplayName {
		t.Fatalf("dispatch forwarded (%d, %s, %s), want the scheduled row's own identity (%d, %s, %s)",
			gotID, gotSHA, gotName, detail.ScheduledRowID, detail.TargetCommitSHA, detail.TargetDisplayName)
	}
}
