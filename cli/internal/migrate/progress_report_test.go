package migrate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParsePendingCountReport(t *testing.T) {
	for _, tc := range []struct {
		line  string
		count int
		ok    bool
	}{
		{line: pendingCountReportLine(0), count: 0, ok: true},
		{line: pendingCountReportLine(17), count: 17, ok: true},
		{line: "ordinary migrate output", ok: false},
		{line: PendingCountReportPrefix + "-1", ok: false},
		{line: PendingCountReportPrefix + "not-a-number", ok: false},
	} {
		count, ok := ParsePendingCountReport(tc.line)
		if count != tc.count || ok != tc.ok {
			t.Errorf("ParsePendingCountReport(%q) = (%d, %v), want (%d, %v)", tc.line, count, ok, tc.count, tc.ok)
		}
	}
}

func TestRunUpNoMigrationFilesReportsZeroPending(t *testing.T) {
	projDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(projDir, "migrations"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv(PendingCountReportEnv, "1")

	var applied int
	var runErr error
	out := captureStdout(t, func() {
		applied, runErr = runUp(projDir, 0, true, false)
	})
	if runErr != nil {
		t.Fatalf("runUp: %v", runErr)
	}
	if applied != 0 {
		t.Fatalf("applied = %d, want 0", applied)
	}
	if !strings.Contains(out, pendingCountReportLine(0)+"\n") {
		t.Fatalf("no-migration success omitted the parent protocol marker; output:\n%s", out)
	}
	if got := os.Getenv(PendingCountReportEnv); got != "" {
		t.Fatalf("%s remained set after reporting: %q", PendingCountReportEnv, got)
	}
}
