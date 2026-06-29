package dbdump

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// ── writeAtomic: the STATBUS-113 AC#2 atomicity core (no docker needed) ────────

// TestWriteAtomic_CommitsOnSuccess: a successful produce publishes the final file
// with the produced content and leaves no .tmp behind.
func TestWriteAtomic_CommitsOnSuccess(t *testing.T) {
	dir := t.TempDir()
	final := filepath.Join(dir, "x.pg_dump")
	err := writeAtomic(final, func(w io.Writer) error {
		_, e := w.Write([]byte("DUMP-BYTES"))
		return e
	})
	if err != nil {
		t.Fatalf("writeAtomic: %v", err)
	}
	if b, err := os.ReadFile(final); err != nil || string(b) != "DUMP-BYTES" {
		t.Fatalf("final content=%q err=%v; want DUMP-BYTES", b, err)
	}
	if _, err := os.Stat(final + ".tmp"); !os.IsNotExist(err) {
		t.Errorf(".tmp must be gone after commit; stat err=%v", err)
	}
}

// TestWriteAtomic_NoPartialOnProduceError: produce fails AFTER writing some bytes
// → NO final file is published and the .tmp is removed. This is the atomicity
// invariant: a failed/killed dump never leaves a corrupt restore source under the
// final name.
func TestWriteAtomic_NoPartialOnProduceError(t *testing.T) {
	dir := t.TempDir()
	final := filepath.Join(dir, "x.pg_dump")
	err := writeAtomic(final, func(w io.Writer) error {
		_, _ = w.Write([]byte("HALF")) // partial output before the failure
		return fmt.Errorf("pg_dump boom")
	})
	if err == nil {
		t.Fatal("writeAtomic must surface the produce error")
	}
	if _, e := os.Stat(final); !os.IsNotExist(e) {
		t.Errorf("no final file may be published on produce error; stat err=%v", e)
	}
	if _, e := os.Stat(final + ".tmp"); !os.IsNotExist(e) {
		t.Errorf(".tmp must be removed on produce error (no partial left); stat err=%v", e)
	}
}

// TestWriteAtomic_RejectsEmptyDump: produce succeeds but writes nothing → an
// empty file is not a valid backup, so it is rejected, no final published, .tmp gone.
func TestWriteAtomic_RejectsEmptyDump(t *testing.T) {
	dir := t.TempDir()
	final := filepath.Join(dir, "x.pg_dump")
	err := writeAtomic(final, func(w io.Writer) error { return nil }) // zero bytes
	if err == nil {
		t.Fatal("an empty dump must be rejected")
	}
	if _, e := os.Stat(final); !os.IsNotExist(e) {
		t.Errorf("empty dump must not be published; stat err=%v", e)
	}
	if _, e := os.Stat(final + ".tmp"); !os.IsNotExist(e) {
		t.Errorf(".tmp must be removed for an empty dump; stat err=%v", e)
	}
}

// ── retention: DumpsToPurge / PurgeDumps keep newest N per prefix ──────────────

func touchDump(t *testing.T, projDir, name string) string {
	t.Helper()
	dir := DumpsDir(projDir)
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}
	return p
}

// TestPurgeDumps_KeepsNewestNPerPrefix: retention keeps the newest N per SOURCE
// prefix (filenames sort lexically = chronologically); two prefixes are pruned
// independently so one slot's history never crowds out another's.
func TestPurgeDumps_KeepsNewestNPerPrefix(t *testing.T) {
	proj := t.TempDir()
	touchDump(t, proj, "no_20260101_000000.pg_dump")
	touchDump(t, proj, "no_20260102_000000.pg_dump")
	touchDump(t, proj, "no_20260103_000000.pg_dump")
	touchDump(t, proj, "no_20260104_000000.pg_dump") // newest no
	touchDump(t, proj, "ma_20260101_000000.pg_dump")
	touchDump(t, proj, "ma_20260102_000000.pg_dump") // newest ma

	deleted, err := PurgeDumps(proj, 2)
	if err != nil {
		t.Fatalf("PurgeDumps: %v", err)
	}
	// keep 2 per prefix → delete the 2 oldest "no" only; "ma" has exactly 2 → kept.
	if len(deleted) != 2 {
		t.Fatalf("deleted %d, want 2: %v", len(deleted), deleted)
	}
	wantDeleted := map[string]bool{
		"no_20260101_000000.pg_dump": true,
		"no_20260102_000000.pg_dump": true,
	}
	for _, p := range deleted {
		if !wantDeleted[filepath.Base(p)] {
			t.Errorf("unexpectedly deleted %s", filepath.Base(p))
		}
	}
	for _, keep := range []string{
		"no_20260103_000000.pg_dump", "no_20260104_000000.pg_dump",
		"ma_20260101_000000.pg_dump", "ma_20260102_000000.pg_dump",
	} {
		if _, err := os.Stat(filepath.Join(DumpsDir(proj), keep)); err != nil {
			t.Errorf("must keep %s: %v", keep, err)
		}
	}
}

// TestDumpsToPurge_BoundaryCounts pins the keepN edges: >=count is a no-op, 0
// selects all, negative errors.
func TestDumpsToPurge_BoundaryCounts(t *testing.T) {
	proj := t.TempDir()
	touchDump(t, proj, "no_20260101_000000.pg_dump")
	touchDump(t, proj, "no_20260102_000000.pg_dump")

	if sel, err := DumpsToPurge(proj, 2); err != nil || len(sel) != 0 {
		t.Errorf("keepN==count must select nothing; got %v err=%v", sel, err)
	}
	if sel, err := DumpsToPurge(proj, 5); err != nil || len(sel) != 0 {
		t.Errorf("keepN>count must select nothing; got %v err=%v", sel, err)
	}
	if sel, err := DumpsToPurge(proj, 0); err != nil || len(sel) != 2 {
		t.Errorf("keepN==0 must select all; got %v err=%v", sel, err)
	}
	if _, err := DumpsToPurge(proj, -1); err == nil {
		t.Error("negative keepN must error")
	}
}

// TestNewestDumpModTime: ok=false with no dumps; with dumps, returns the most
// recent mtime (the service's due-check state).
func TestNewestDumpModTime(t *testing.T) {
	proj := t.TempDir()
	if _, ok := NewestDumpModTime(proj); ok {
		t.Error("no dumps → ok must be false")
	}
	older := touchDump(t, proj, "no_20260101_000000.pg_dump")
	newer := touchDump(t, proj, "no_20260102_000000.pg_dump")
	old := time.Now().Add(-48 * time.Hour)
	recent := time.Now().Add(-1 * time.Hour)
	if err := os.Chtimes(older, old, old); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(newer, recent, recent); err != nil {
		t.Fatal(err)
	}
	got, ok := NewestDumpModTime(proj)
	if !ok {
		t.Fatal("ok must be true with dumps present")
	}
	// Newest is the ~1h-old file, not the 48h-old one.
	if time.Since(got) > 2*time.Hour {
		t.Errorf("newest mod time = %v (age %v); want the ~1h-old dump", got, time.Since(got))
	}
}
