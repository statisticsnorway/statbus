package upgrade

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// TestRollbackConnectionLifecycleIsNilSafe_STATBUS338 is the rune rc.02
// regression pin. executeUpgrade deliberately closes and clears queryConn before
// the consistent backup. A returned pre-swap error then entered rollback, whose
// recovery_attempts read dereferenced that nil pointer; Run's cleanup defers did
// the same while unwinding and hid the original git error behind a panic.
func TestRollbackConnectionLifecycleIsNilSafe_STATBUS338(t *testing.T) {
	d := &Service{projDir: t.TempDir(), queryConn: nil}
	if got := d.rollbackRecoveryAttempts(context.Background(), 338); got != 0 {
		t.Fatalf("nil-connection recovery_attempts read = %d, want best-effort zero", got)
	}

	src := readUpgradeServiceSource(t)
	rollbackBody := extractFuncBody(t, src, "func (d *Service) rollback(")
	if !strings.Contains(rollbackBody, "d.rollbackRecoveryAttempts(ctx, id)") {
		t.Error("rollback must route its recovery_attempts read through the nil-safe helper before restoring")
	}

	runBody := extractFuncBody(t, src, "func (d *Service) Run(")
	for _, guard := range []string{
		"if d.listenConn != nil",
		"if d.queryConn != nil",
	} {
		if !strings.Contains(runBody, guard) {
			t.Errorf("Run cleanup must contain %q; executeUpgrade clears both connections during a claimed upgrade, so an unconditional deferred Close repanics while unwinding the original error", guard)
		}
	}
}

func gitSTATBUS338(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", testgit.Args(args...)...)
	cmd.Dir = dir
	cmd.Env = testgit.Env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
	return strings.TrimSpace(string(out))
}

func newMissingCommitFixtureSTATBUS338(t *testing.T) (local, commitSHA string) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	origin := t.TempDir()
	gitSTATBUS338(t, origin, "init", "-q", "-b", "master")
	gitSTATBUS338(t, origin, "commit", "-q", "--allow-empty", "-m", "target commit")
	commitSHA = gitSTATBUS338(t, origin, "rev-parse", "HEAD")

	local = t.TempDir()
	gitSTATBUS338(t, local, "init", "-q", "-b", "master")
	gitSTATBUS338(t, local, "remote", "add", "origin", origin)
	return local, commitSHA
}

func TestEnsureUpgradeCommitObjects_LocalFastPath_STATBUS338(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	local := t.TempDir()
	gitSTATBUS338(t, local, "init", "-q", "-b", "master")
	gitSTATBUS338(t, local, "commit", "-q", "--allow-empty", "-m", "already local")
	commitSHA := gitSTATBUS338(t, local, "rev-parse", "HEAD")

	fetchCalls := 0
	d := &Service{
		projDir: local,
		fetchCommitObjects: func(context.Context, io.Writer, string) error {
			fetchCalls++
			return errors.New("network must not be touched")
		},
		fetchRetryWait: func(context.Context, time.Duration) error {
			t.Fatal("fast path must not enter retry backoff")
			return nil
		},
	}
	if err := d.ensureUpgradeCommitObjects(context.Background(), io.Discard, commitSHA); err != nil {
		t.Fatalf("already-local target must be a no-op: %v", err)
	}
	if fetchCalls != 0 {
		t.Fatalf("already-local target made %d fetch call(s), want zero", fetchCalls)
	}
}

func TestEnsureUpgradeCommitObjects_TransientTwiceThenSucceeds_STATBUS338(t *testing.T) {
	local, commitSHA := newMissingCommitFixtureSTATBUS338(t)
	d := &Service{projDir: local}
	fetchCalls := 0
	waitCalls := 0
	d.fetchRetryWait = func(context.Context, time.Duration) error {
		waitCalls++
		return nil
	}
	d.fetchCommitObjects = func(ctx context.Context, logWriter io.Writer, gotSHA string) error {
		fetchCalls++
		if fetchCalls <= 2 {
			return fmt.Errorf("remote transport blip %d", fetchCalls)
		}
		return d.fetchWithStallDetection(ctx, logWriter, gotSHA)
	}

	if err := d.ensureUpgradeCommitObjects(context.Background(), io.Discard, commitSHA); err != nil {
		t.Fatalf("third fetch attempt should converge: %v", err)
	}
	if fetchCalls != 3 || waitCalls != 2 {
		t.Fatalf("bounded retry shape = %d fetches/%d waits, want 3 fetches/2 waits", fetchCalls, waitCalls)
	}
	if !d.commitObjectPresent(commitSHA) {
		t.Fatal("successful retry returned before the target commit object was present locally")
	}
}

func TestEnsureUpgradeCommitObjects_PermanentFailureExhausts_STATBUS338(t *testing.T) {
	local, commitSHA := newMissingCommitFixtureSTATBUS338(t)
	const gitFailure = "remote: synthetic GitHub HTTP 503 from rune signature"
	fetchCalls := 0
	waitCalls := 0
	d := &Service{
		projDir: local,
		fetchCommitObjects: func(context.Context, io.Writer, string) error {
			fetchCalls++
			return errors.New(gitFailure)
		},
		fetchRetryWait: func(context.Context, time.Duration) error {
			waitCalls++
			return nil
		},
	}

	err := d.ensureUpgradeCommitObjects(context.Background(), io.Discard, commitSHA)
	if err == nil {
		t.Fatal("permanent fetch failure must exhaust with an error")
	}
	if fetchCalls != preswapFetchMaxAttempts || waitCalls != preswapFetchMaxAttempts-1 {
		t.Fatalf("permanent failure made %d fetches/%d waits, want %d/%d", fetchCalls, waitCalls, preswapFetchMaxAttempts, preswapFetchMaxAttempts-1)
	}
	for _, want := range []string{"failed after 3 attempts", gitFailure} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("exhausted error lost %q: %v", want, err)
		}
	}
}

func TestFetchWithStallDetection_ReturnsGitOutput_STATBUS338(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	local := t.TempDir()
	gitSTATBUS338(t, local, "init", "-q", "-b", "master")
	missingRemote := filepath.Join(t.TempDir(), "missing-origin")
	gitSTATBUS338(t, local, "remote", "add", "origin", missingRemote)

	d := &Service{projDir: local}
	err := d.fetchWithStallDetection(context.Background(), io.Discard, strings.Repeat("b", 40))
	if err == nil {
		t.Fatal("fetch from a missing origin must fail")
	}
	for _, want := range []string{"git output:", "does not appear to be a git repository"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("returned fetch error lost git stderr %q: %v", want, err)
		}
	}
}

func TestPreswapFetchRunsBeforeMaintenance_STATBUS338(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) executeUpgrade(")
	ensureAt := strings.Index(body, "d.ensureUpgradeCommitObjects(")
	readOnlyAt := strings.Index(body, "d.setDatabaseReadOnly(ctx, true)")
	maintenanceAt := strings.Index(body, "d.setMaintenance(true, maintenanceContent)")
	backupAt := strings.Index(body, "d.backupDatabase(")
	flagAt := strings.Index(body, "d.writeUpgradeFlag(")
	if ensureAt < 0 || readOnlyAt < 0 || maintenanceAt < 0 || backupAt < 0 || flagAt < 0 {
		t.Fatalf("could not locate target-object/flag/read-only/maintenance/backup sequence in executeUpgrade")
	}
	if flagAt >= ensureAt || ensureAt >= readOnlyAt || readOnlyAt >= maintenanceAt || maintenanceAt >= backupAt {
		t.Fatalf("unsafe executeUpgrade order: flag=%d ensure=%d readOnly=%d maintenance=%d backup=%d; target objects must be ensured after ownership but before any downtime, while existing state-transition ordering remains intact", flagAt, ensureAt, readOnlyAt, maintenanceAt, backupAt)
	}
	if n := strings.Count(body, "d.ensureUpgradeCommitObjects("); n != 1 {
		t.Fatalf("executeUpgrade must ensure target objects exactly once, found %d calls", n)
	}
}

func TestReturnedFetchErrorSurvivesPreswapRecovery_STATBUS338(t *testing.T) {
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0o755); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(338, strings.Repeat("a", 40), []string{"v2026.09.0-rc.02"}, "test", string(TriggerService), false); err != nil {
		t.Fatalf("writeUpgradeFlag: %v", err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })

	const gitFailure = "remote: synthetic GitHub HTTP 503 from rune signature"
	original := ErrGitFetchRetryable + ": git fetch aaaaaaaa failed after 3 attempts: " + gitFailure
	if err := d.recordOriginalError(original); err != nil {
		t.Fatalf("recordOriginalError: %v", err)
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatalf("ReadFlagFile: %v", err)
	}
	got := preSwapRecoveryReason(*flag)
	if got != original {
		t.Fatalf("PreSwap recovery reason = %q, want original returned error %q", got, original)
	}
	if strings.Contains(got, ErrInstallPreconditionFailed) {
		t.Fatalf("original git failure was replaced by the false deterministic class: %q", got)
	}
	if !retryableRollbackReason(got) {
		t.Fatalf("preserved fetch failure must classify retryable: %q", got)
	}

	// The terminal writer receives errMsg, and restoreAndFinalize initializes it
	// from the preserved reason. This source pin connects the behavioral flag proof
	// above to the public.upgrade.error write without requiring a live test DB.
	restoreBody := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) restoreAndFinalize(")
	for _, want := range []string{
		"errMsg := reason",
		"rollback_finish_pending_at = now()",
		"d.writeRollbackTerminal(",
	} {
		if !strings.Contains(restoreBody, want) {
			t.Errorf("restoreAndFinalize lost the original-error-to-terminal-row contract; missing %q", want)
		}
	}
	finalizerBody := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) finalizePendingRollback(")
	if !strings.Contains(finalizerBody, "rollbackFinalError(errorText)") {
		t.Error("serialized rollback finalizer no longer derives final guidance from the preserved pending error")
	}
	guidanceBody := extractFuncBody(t, readUpgradeServiceSource(t), "func rollbackFinalError(")
	for _, want := range []string{"retryableRollbackReason(reason)", "It is safe to schedule this same version again"} {
		if !strings.Contains(guidanceBody, want) {
			t.Errorf("rollbackFinalError lost retryable original-error guidance; missing %q", want)
		}
	}
}

func TestManifestSweepTags_BoundsHistoricalPrereleases_STATBUS338(t *testing.T) {
	tags := make([]GitTag, 0, 200)
	for i := 1; i <= 196; i++ {
		tags = append(tags, GitTag{TagName: fmt.Sprintf("v2026.07.%d-rc.01", i)})
	}
	tags = append(tags,
		GitTag{TagName: "v2026.08.1-rc.01"}, // installed, exclude
		GitTag{TagName: "v2026.08.1"},       // promotion, newer
		GitTag{TagName: "v2026.09.0-rc.01"}, // genuinely newer
	)

	got := manifestSweepTags(tags, "v2026.08.1-rc.01")
	if len(got) != 2 {
		t.Fatalf("manifest sweep probed %d tags, want only the 2 newer tags out of %d: %#v", len(got), len(tags), got)
	}
	if got[0].TagName != "v2026.08.1" || got[1].TagName != "v2026.09.0-rc.01" {
		t.Fatalf("manifest sweep did not preserve the newer-tag order: %#v", got)
	}
	if got := manifestSweepTags(tags, "deadbeef"); len(got) != 0 {
		t.Fatalf("unorderable installed commit must trigger zero ranked manifest probes, got %d", len(got))
	}

	discoverBody := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) discover(")
	for _, want := range []string{
		"manifestTags := manifestSweepTags(filtered, currentVersion)",
		"for _, t := range manifestTags",
	} {
		if !strings.Contains(discoverBody, want) {
			t.Errorf("discover does not use the bounded tag set for its manifest loop; missing %q", want)
		}
	}
}
