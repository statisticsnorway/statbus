package upgrade

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Tests for the rc.42 actionability fixes (commits b465ee98f + c7c44f503):
//   - captureContainerLogs writes per-service files into the right dir
//   - healthCheck logs per-attempt status code + body excerpt via progress
//   - removeUpgradeFlag removes the file (symmetrised with ReleaseInstallFlag)

// TestCaptureContainerLogs_PathComputation verifies the helper creates
// the expected sibling directory next to the per-upgrade log file and
// writes one file per requested service. We pass services that don't
// exist as docker compose services so the docker call fails fast and
// we exercise the "# capture failed" fallback path — which is enough to
// confirm directory + file path computation is correct.
func TestCaptureContainerLogs_PathComputation(t *testing.T) {
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp", "upgrade-logs"), 0755); err != nil {
		t.Fatal(err)
	}

	progress := NewUpgradeLog(projDir, 99, "v0.0.0-rc.test", time.Date(2026, 4, 22, 1, 30, 0, 0, time.UTC))
	if progress == nil || progress.RelPath() == "" {
		t.Fatal("NewUpgradeLog returned nil or empty relPath")
	}

	captureContainerLogs(projDir, progress, []string{"svc-a", "svc-b"})

	base := strings.TrimSuffix(progress.RelPath(), filepath.Ext(progress.RelPath()))
	dir := filepath.Join(projDir, "tmp", "upgrade-logs", base+".containers")

	if _, err := os.Stat(dir); err != nil {
		t.Fatalf("expected containers dir at %s, got: %v", dir, err)
	}

	for _, svc := range []string{"svc-a", "svc-b"} {
		path := filepath.Join(dir, svc+".log")
		if _, err := os.Stat(path); err != nil {
			t.Errorf("expected per-service log at %s, got: %v", path, err)
		}
	}
}

// TestCaptureContainerLogs_NoProgress verifies the helper short-circuits
// when progress is nil (no log path → no work to do).
func TestCaptureContainerLogs_NoProgress(t *testing.T) {
	projDir := t.TempDir()
	captureContainerLogs(projDir, nil, []string{"svc-a"})
	// Should not have created tmp/upgrade-logs at all.
	if _, err := os.Stat(filepath.Join(projDir, "tmp", "upgrade-logs")); !os.IsNotExist(err) {
		t.Errorf("expected no tmp/upgrade-logs created with nil progress; stat err=%v", err)
	}
}

// TestHealthCheck_PerAttemptLogging verifies that each failed attempt
// writes a progress line containing the status code + body excerpt.
// Final error includes the last attempt's detail rather than the
// pre-fix generic "after N attempts".
func TestHealthCheck_PerAttemptLogging(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte(`{"code":"PGRST002","message":"Could not connect to PostgREST"}`))
	}))
	defer srv.Close()

	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp", "upgrade-logs"), 0755); err != nil {
		t.Fatal(err)
	}
	progress := NewUpgradeLog(projDir, 100, "v0.0.0-rc.health", time.Now())
	if progress == nil {
		t.Fatal("NewUpgradeLog returned nil")
	}

	d := &Service{cachedURL: srv.URL}
	err := d.healthCheck(progress, 3, 1*time.Millisecond)
	if err == nil {
		t.Fatal("expected healthCheck to return error after retries; got nil")
	}

	// Final error must mention the last attempt's detail (status + body
	// excerpt), not just the pre-fix generic "after N attempts".
	if !strings.Contains(err.Error(), "status=503") {
		t.Errorf("expected final error to include status code, got: %v", err)
	}
	if !strings.Contains(err.Error(), "PGRST002") {
		t.Errorf("expected final error to include response body excerpt, got: %v", err)
	}

	// Each attempt should have written a per-attempt line to the
	// progress log with the status + body.
	logBytes, err := os.ReadFile(progress.AbsPath())
	if err != nil {
		t.Fatalf("read progress log: %v", err)
	}
	logStr := string(logBytes)
	want := []string{
		"Health check attempt 1/3 failed",
		"Health check attempt 2/3 failed",
		"Health check attempt 3/3 failed",
		"status=503",
		"PGRST002",
	}
	for _, w := range want {
		if !strings.Contains(logStr, w) {
			t.Errorf("expected progress log to contain %q; full log:\n%s", w, logStr)
		}
	}
}

// TestRemoveUpgradeFlag_RemovesFile verifies the symmetry change to
// removeUpgradeFlag (commit c7c44f503): after release the file is
// gone, not just the flock. Eliminates the ghost-flag class that the
// old behaviour created.
func TestRemoveUpgradeFlag_RemovesFile(t *testing.T) {
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}

	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(42, "abc123def456", "v0.0.0-test", "test", string(TriggerService)); err != nil {
		t.Fatalf("writeUpgradeFlag failed: %v", err)
	}

	flagPath := d.flagPath()
	if _, err := os.Stat(flagPath); err != nil {
		t.Fatalf("flag file should exist after writeUpgradeFlag; stat err: %v", err)
	}

	d.removeUpgradeFlag()

	if _, err := os.Stat(flagPath); !os.IsNotExist(err) {
		t.Errorf("flag file should be REMOVED after removeUpgradeFlag (symmetric with ReleaseInstallFlag); stat err=%v", err)
	}

	// Re-acquire should succeed (flock was released, file is gone).
	if err := d.writeUpgradeFlag(43, "abc123def457", "v0.0.0-test2", "test", string(TriggerService)); err != nil {
		t.Errorf("re-acquire after removeUpgradeFlag should succeed; got: %v", err)
	}
	d.removeUpgradeFlag()
}

// TestRemoveUpgradeFlag_IgnoresNilLock verifies the helper is safe to
// call when no flag was acquired (some failUpgrade callers run before
// writeUpgradeFlag during pre-flight). Documented as idempotent.
func TestRemoveUpgradeFlag_IgnoresNilLock(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir}
	// No writeUpgradeFlag call. removeUpgradeFlag must not panic.
	d.removeUpgradeFlag()
}

// flagPath is already defined in service.go — these tests reuse it.
