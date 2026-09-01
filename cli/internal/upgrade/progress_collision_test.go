package upgrade

import (
	"bytes"
	"os"
	"strings"
	"testing"
	"time"
)

func TestNewUpgradeLogSameSecondUsesDistinctPathWithoutTruncation(t *testing.T) {
	projDir := t.TempDir()
	startTime := time.Date(2026, 9, 1, 12, 34, 56, 0, time.UTC)

	first := NewUpgradeLog(projDir, 333, "v2026.09.0-rc.1", startTime)
	if first == nil || first.RelPath() == "" {
		t.Fatal("first NewUpgradeLog returned no path")
	}
	first.Write("first attempt marker")
	first.Close()

	before, err := os.ReadFile(first.AbsPath())
	if err != nil {
		t.Fatalf("read first log before collision: %v", err)
	}
	if !strings.Contains(string(before), "first attempt marker") {
		t.Fatal("first log is missing its attempt marker before the collision")
	}

	second := NewUpgradeLog(projDir, 333, "v2026.09.0-rc.1", startTime)
	if second == nil || second.RelPath() == "" {
		t.Fatal("second NewUpgradeLog returned no path")
	}
	second.Close()

	if first.RelPath() == second.RelPath() {
		t.Fatalf("same-second upgrade logs reused path %q", first.RelPath())
	}
	if !strings.HasSuffix(second.RelPath(), "-1.log") {
		t.Fatalf("second same-second path = %q, want numeric suffix before .log", second.RelPath())
	}

	after, err := os.ReadFile(first.AbsPath())
	if err != nil {
		t.Fatalf("read first log after collision: %v", err)
	}
	if !bytes.Equal(after, before) {
		t.Fatal("creating the second same-second log changed the first log")
	}
}
