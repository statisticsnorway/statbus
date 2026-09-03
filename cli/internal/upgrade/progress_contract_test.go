package upgrade

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

func TestSetMaintenanceReturnsFilesystemFailures(t *testing.T) {
	t.Run("activation", func(t *testing.T) {
		home := t.TempDir()
		t.Setenv("HOME", home)
		if err := os.WriteFile(filepath.Join(home, maintenanceFlagDir), []byte("not a directory"), 0o644); err != nil {
			t.Fatal(err)
		}
		d := &Service{}
		if err := d.setMaintenance(true, "upgrade 1 to test\n{}\ncommand\n"); err == nil {
			t.Fatal("setMaintenance accepted an unwritable maintenance directory")
		}
	})

	t.Run("removal", func(t *testing.T) {
		home := t.TempDir()
		t.Setenv("HOME", home)
		if err := os.MkdirAll(maintenanceFlagHostPath(), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(maintenanceFlagHostPath(), "child"), []byte("keeps directory non-empty"), 0o644); err != nil {
			t.Fatal(err)
		}
		d := &Service{}
		if err := d.setMaintenance(false, ""); err == nil {
			t.Fatal("setMaintenance discarded a flag-removal failure")
		}
	})
}

func TestReleaseUpgradeFlagLockKeepingFile(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(347, strings.Repeat("a", 40), []string{"vtest"}, "test", "test", false); err != nil {
		t.Fatalf("writeUpgradeFlag: %v", err)
	}

	d.releaseUpgradeFlagLockKeepingFile()
	if d.flagLock != nil {
		t.Fatal("live flag lock remains attached after recovery-marker preservation")
	}
	if _, err := os.Stat(d.flagPath()); err != nil {
		t.Fatalf("recovery marker must remain on disk: %v", err)
	}

	f, err := os.OpenFile(d.flagPath(), os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatalf("preserved marker still has a live flock: %v", err)
	}
}

func TestRollbackFinishFlagUnlinkFailureStaysCleanupOnly(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(347, strings.Repeat("a", 40), []string{"vtest"}, "test", "test", false); err != nil {
		t.Fatalf("writeUpgradeFlag: %v", err)
	}

	unlinkErr := errors.New("injected unlink failure")
	d.removeFile = func(path string) error {
		if path != d.flagPath() {
			t.Fatalf("remove called for %q, want %q", path, d.flagPath())
		}
		return unlinkErr
	}
	if err := d.removeUpgradeFlag(); !errors.Is(err, unlinkErr) {
		t.Fatalf("removeUpgradeFlag error = %v, want %v", err, unlinkErr)
	}
	if d.flagLock != nil {
		t.Fatal("failed unlink retained a live flock instead of a free cleanup marker")
	}
	if _, err := os.Stat(d.flagPath()); err != nil {
		t.Fatalf("failed unlink did not preserve the marker: %v", err)
	}

	// The retry is cleanup-only: remove exactly this rollback's free marker.
	d.removeFile = nil
	if err := d.clearRollbackFinishFlag(347); err != nil {
		t.Fatalf("clearRollbackFinishFlag retry: %v", err)
	}
	if _, err := os.Stat(d.flagPath()); !os.IsNotExist(err) {
		t.Fatalf("cleanup-only retry left the marker behind: %v", err)
	}
}

func TestRollbackFinishCleanupDoesNotRemoveAnotherUpgradeMarker(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(348, strings.Repeat("b", 40), []string{"vother"}, "test", "test", false); err != nil {
		t.Fatalf("writeUpgradeFlag: %v", err)
	}
	d.releaseUpgradeFlagLockKeepingFile()

	if err := d.clearRollbackFinishFlag(347); err != nil {
		t.Fatalf("clearRollbackFinishFlag for a different id: %v", err)
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatalf("read other upgrade marker: %v", err)
	}
	if flag == nil || flag.ID != 348 {
		t.Fatalf("cleanup for upgrade 347 removed or replaced upgrade 348 marker: %#v", flag)
	}
}

func TestRollbackFinalErrorContracts(t *testing.T) {
	reason := ErrGitFetchRetryable + ": remote closed connection"
	final := rollbackFinalError(reason)
	for _, want := range []string{reason, "running normally on the old version", "safe to schedule this same version again"} {
		if !strings.Contains(final, want) {
			t.Fatalf("final retryable rollback guidance %q lacks %q", final, want)
		}
	}

	hardFinal := rollbackFinalError("migration failed")
	if !strings.Contains(hardFinal, "do NOT re-schedule it") {
		t.Fatalf("hard rollback guidance lost deterministic-failure advice: %q", hardFinal)
	}
}

func TestMaintenanceFlagContent(t *testing.T) {
	snapshot := upgradeClaimSnapshot{
		ID:                43093,
		CommitVersion:     "v2026.09.0-rc.12",
		CommitSHA:         "2309f6e12abcdef",
		FromCommitVersion: "v2026.08.1-rc.01",
		StartedAt:         time.Date(2026, 9, 3, 8, 28, 23, 0, time.UTC),
		ImmutableJSON:     `{"id":43093,"commit_version":"v2026.09.0-rc.12","commit_sha":"2309f6e12abcdef","from_commit_version":"v2026.08.1-rc.01","started_at":"2026-09-03T08:28:23+00:00"}`,
	}

	got, err := maintenanceFlagContent(snapshot)
	if err != nil {
		t.Fatalf("maintenanceFlagContent: %v", err)
	}
	want := strings.Join([]string{
		"upgrade 43093 to v2026.09.0-rc.12",
		snapshot.ImmutableJSON,
		`echo "SELECT to_json(t) FROM (SELECT id, state, completed_at, rolled_back_at, error FROM public.upgrade WHERE id = 43093) AS t;" | ./sb psql -t -A`,
	}, "\n") + "\n"
	if got != want {
		t.Fatalf("maintenance flag content mismatch\n--- got ---\n%s--- want ---\n%s", got, want)
	}
}

func TestMaintenanceFlagContentRequiresDatabaseJSON(t *testing.T) {
	for _, immutableJSON := range []string{"", "not-json"} {
		_, err := maintenanceFlagContent(upgradeClaimSnapshot{
			ID:            7,
			CommitVersion: "v2026.09.0-rc.12",
			ImmutableJSON: immutableJSON,
		})
		if err == nil {
			t.Fatalf("maintenanceFlagContent accepted immutable JSON %q", immutableJSON)
		}
	}
}

func TestSuccessfulUpgradeFinishingNarrativeMatchesTargetOrder(t *testing.T) {
	t.Setenv("HOME", "/home/statbus")
	narrative := newSuccessfulUpgradeFinishingNarrative(
		"v2026.09.0-rc.12",
		"/home/statbus/statbus-maintenance/active",
		"/home/statbus/statbus/tmp/upgrade-in-progress.json",
	)

	got := narrative.successLines(
		`ALTER DATABASE "statbus_no" SET default_transaction_read_only = off`,
		3661*time.Millisecond,
	)
	want := []string{
		"Finishing:",
		"  Lifting maintenance mode ... ok",
		"    removed: ~/statbus-maintenance/active",
		"  Recording the successful upgrade in the database ... ok",
		"  Unblocking SQL writes ... ok",
		`    ran: ALTER DATABASE "statbus_no" SET default_transaction_read_only = off`,
		"  Releasing upgrade lock ... ok",
		"    removed: ~/statbus/tmp/upgrade-in-progress.json",
		"  Applying configuration and service updates ... ok (3.7s)",
		"Upgrade to v2026.09.0-rc.12 complete.",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("finishing narrative mismatch\n--- got ---\n%s\n--- want ---\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
	if last := got[len(got)-1]; last != narrative.completeLine() {
		t.Fatalf("completion line must be last, got %q", last)
	}
}

func TestOperatorServiceStateLinesMatchesTargetShape(t *testing.T) {
	got := operatorServiceStateLines([]string{
		"db: old version not running, new version not started yet",
		"app: old version not running, new version not started yet",
		"worker: old version not running, new version not started yet",
		"proxy: old version running, new version not started yet",
		"rest: old version not running, new version not started yet",
	})
	want := []string{
		"app: old version not running, new version not started yet",
		"worker: old version not running, new version not started yet",
		"proxy: old version running, new version not started yet",
		"rest: old version not running, new version not started yet",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("operator service-state lines:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestFilteredLineWriterPromotesMigrationCount(t *testing.T) {
	var output bytes.Buffer
	count := -1
	writer := newFilteredLineWriter(&output, func(line string) bool {
		parsed, ok := migrate.ParsePendingCountReport(line)
		if ok {
			count = parsed
		}
		return ok
	})

	for _, chunk := range []string{"ordinary one\nSTATBUS_MIGRATE_", "PENDING_COUNT=7\nordinary two", "\n"} {
		if _, err := writer.Write([]byte(chunk)); err != nil {
			t.Fatalf("Write(%q): %v", chunk, err)
		}
	}
	if err := writer.Flush(); err != nil {
		t.Fatalf("Flush: %v", err)
	}
	if count != 7 {
		t.Fatalf("promoted count = %d, want 7", count)
	}
	if got, want := output.String(), "ordinary one\nordinary two\n"; got != want {
		t.Fatalf("filtered output = %q, want %q", got, want)
	}
}

func TestRollbackCompletionErrorsRefuseHealthyTerminalForEveryRequiredBoundary(t *testing.T) {
	boom := errors.New("boom")
	for _, tc := range []struct {
		name string
		err  rollbackCompletionErrors
		want string
	}{
		{name: "database restore", err: rollbackCompletionErrors{databaseRestore: boom}, want: "DB snapshot restore failed"},
		{name: "services start", err: rollbackCompletionErrors{servicesStart: boom}, want: "services did not come back up"},
		{name: "database health", err: rollbackCompletionErrors{databaseHealth: boom}, want: "restored database did not become healthy"},
		{name: "reconnect", err: rollbackCompletionErrors{reconnect: boom}, want: "upgrade service did not reconnect to the restored database"},
		{name: "maintenance", err: rollbackCompletionErrors{maintenance: boom}, want: "maintenance mode did not lift"},
		{name: "read only", err: rollbackCompletionErrors{readOnly: boom}, want: "SQL writes remained blocked"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if !tc.err.degraded() {
				t.Fatal("rollback was classified healthy despite a failed completion boundary")
			}
			if got := tc.err.details(); !reflect.DeepEqual(got, []string{tc.want}) {
				t.Fatalf("details = %#v, want %#v", got, []string{tc.want})
			}
		})
	}
	if clean := (rollbackCompletionErrors{}); clean.degraded() || len(clean.details()) != 0 {
		t.Fatalf("clean rollback classified degraded: %#v", clean.details())
	}
}
