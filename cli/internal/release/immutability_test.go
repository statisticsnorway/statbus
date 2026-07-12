package release

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// initGitRepo creates a real git repo in a temp dir with one committed file,
// so FileIsDirty's git-diff mechanics run against real git state — no
// database, no network, no shared/production repo touched.
func initGitRepo(t *testing.T) (dir, relPath string) {
	t.Helper()
	dir = t.TempDir()
	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	run("init", "-q")
	run("config", "user.email", "test@example.com")
	run("config", "user.name", "test")
	relPath = filepath.Join("migrations", "20260101000000_desc.up.sql")
	full := filepath.Join(dir, relPath)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte("-- committed\nSELECT 1;\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	run("add", relPath)
	run("commit", "-q", "-m", "init")
	return dir, relPath
}

// TestFileIsDirty_Clean: a file identical to HEAD is reported clean — the
// STATBUS-156 signal that a content_hash mismatch here cannot be a live edit.
func TestFileIsDirty_Clean(t *testing.T) {
	dir, relPath := initGitRepo(t)
	dirty, err := FileIsDirty(dir, relPath)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dirty {
		t.Errorf("expected clean (dirty=false), got dirty=true")
	}
}

// TestFileIsDirty_Dirty: a file modified after commit (a live edit in
// progress) is reported dirty — the genuine-edit case that must still hit
// the ordinary immutability refusal, never the stale-cache fallback.
func TestFileIsDirty_Dirty(t *testing.T) {
	dir, relPath := initGitRepo(t)
	full := filepath.Join(dir, relPath)
	if err := os.WriteFile(full, []byte("-- committed\nSELECT 1;\n-- edited locally\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	dirty, err := FileIsDirty(dir, relPath)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !dirty {
		t.Errorf("expected dirty=true for a locally modified file, got dirty=false")
	}
}

// TestFileIsDirty_NotAGitRepo: git itself failing (no .git here) must surface
// as a genuine error, never silently reported as clean — an uncertain read
// must not let the caller default toward the auto-recovery path.
func TestFileIsDirty_NotAGitRepo(t *testing.T) {
	dir := t.TempDir()
	if _, err := FileIsDirty(dir, "migrations/whatever.up.sql"); err == nil {
		t.Errorf("expected an error outside a git repo, got nil")
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Empty(t *testing.T) {
	cases := []string{"", "   ", "\t\n", ",", "  ,  ,  "}
	for _, in := range cases {
		got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions(in)
		if err != nil {
			t.Errorf("input %q: unexpected error: %v", in, err)
		}
		if len(got) != 0 {
			t.Errorf("input %q: expected empty map, got %v", in, got)
		}
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Single(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("20260521112759")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || !got[20260521112759] {
		t.Errorf("expected {20260521112759: true}, got %v", got)
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Multi(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("20260521112759,20260522080000")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 2 {
		t.Errorf("expected 2 entries, got %d (%v)", len(got), got)
	}
	if !got[20260521112759] || !got[20260522080000] {
		t.Errorf("missing expected entries: got %v", got)
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Whitespace(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("  20260521112759  ,  20260522080000  ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !got[20260521112759] || !got[20260522080000] {
		t.Errorf("expected both entries; got %v", got)
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Garbage(t *testing.T) {
	cases := []string{
		"not-a-number",
		"20260521-112759",    // dash inside (typo a real operator might make)
		"20260521112759,abc", // mixed valid + garbage
		"abc,20260521112759", // garbage first
		"20260521112759.99",  // float-like
		"0x123",              // hex
	}
	for _, in := range cases {
		_, err := ParseIntentionallyFixBrokenImmutableMigrationVersions(in)
		if err == nil {
			t.Errorf("input %q: expected error, got nil", in)
			continue
		}
		if !strings.Contains(err.Error(), IntentionallyFixBrokenImmutableMigrationEnvVar) {
			t.Errorf("input %q: error %q missing env-var name", in, err.Error())
		}
		if !strings.Contains(err.Error(), "14-digit") {
			t.Errorf("input %q: error %q missing format hint", in, err.Error())
		}
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_DuplicatesIgnored(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("20260521112759,20260521112759")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || !got[20260521112759] {
		t.Errorf("expected single entry, got %v", got)
	}
}

func TestIntentionallyFixBrokenImmutableMigrationEnvVar_Constant(t *testing.T) {
	// Lock the env-var name. If someone renames it, this test surfaces
	// the change loudly — every doc/operator reference points at the
	// exact string below.
	want := "STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION"
	if IntentionallyFixBrokenImmutableMigrationEnvVar != want {
		t.Errorf("IntentionallyFixBrokenImmutableMigrationEnvVar = %q, want %q", IntentionallyFixBrokenImmutableMigrationEnvVar, want)
	}
}
