package upgrade

import (
	"bytes"
	"os"
	"strings"
	"testing"
	"time"
)

func TestNewInstallLogSameStartPreservesEarlierAttribution(t *testing.T) {
	dir := t.TempDir()
	start := time.Date(2026, 10, 6, 13, 0, 0, 0, time.UTC)
	first := NewInstallLog(dir, "v2026.10.0", start)
	first.Write("original completion timestamp, witness and event references")
	first.Close()
	before, err := os.ReadFile(first.AbsPath())
	if err != nil {
		t.Fatal(err)
	}
	for _, suffix := range []string{"-1.log", "-2.log"} {
		retry := NewInstallLog(dir, "v2026.10.0", start)
		retry.Close()
		if retry.RelPath() == first.RelPath() || !strings.HasSuffix(retry.RelPath(), suffix) {
			t.Fatalf("retry path=%s, want distinct %s", retry.RelPath(), suffix)
		}
		after, err := os.ReadFile(first.AbsPath())
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(before, after) {
			t.Fatal("same-start retry overwrote original attribution")
		}
	}
}
