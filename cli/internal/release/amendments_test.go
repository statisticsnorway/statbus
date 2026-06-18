package release

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeAmendments writes content to <dir>/migrations/amendments.tsv and returns dir.
func writeAmendments(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	mdir := filepath.Join(dir, "migrations")
	if err := os.MkdirAll(mdir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(mdir, "amendments.tsv"), []byte(content), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
	return dir
}

// A MISSING file is the normal case — no amendments declared → empty set, no error.
func TestParseAmendmentsFile_Missing(t *testing.T) {
	got, err := ParseAmendmentsFile(t.TempDir())
	if err != nil {
		t.Fatalf("missing file should not error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty set, got %v", got)
	}
}

// Header-only / comments / blanks → empty set (the committed file ships this way
// until the first amendment).
func TestParseAmendmentsFile_HeaderOnly(t *testing.T) {
	dir := writeAmendments(t, "# comment\n#\tversion\tamending_release\treason\n\n   \n")
	got, err := ParseAmendmentsFile(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("comments/blanks only → expected empty, got %v", got)
	}
}

// Valid rows: tab-separated with audit metadata, a row whose reason has spaces,
// and a version-only row (audit fields optional). Only the version is parsed.
func TestParseAmendmentsFile_Rows(t *testing.T) {
	dir := writeAmendments(t,
		"# header\n"+
			"20260521112759\tv2026.06.1\tV timed out on >1M-row installs; same result, faster\n"+
			"20260522080000\t-\tpending tag; a reason with several spaces\n"+
			"20260523090000\n")
	got, err := ParseAmendmentsFile(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, v := range []int64{20260521112759, 20260522080000, 20260523090000} {
		if !got[v] {
			t.Errorf("missing version %d in %v", v, got)
		}
	}
	if len(got) != 3 {
		t.Errorf("expected 3 entries, got %d (%v)", len(got), got)
	}
}

// A malformed version fails LOUDLY (a typo must never silently widen the gate),
// naming the file + the format hint.
func TestParseAmendmentsFile_Malformed(t *testing.T) {
	dir := writeAmendments(t, "not-a-version\tv1\treason\n")
	_, err := ParseAmendmentsFile(dir)
	if err == nil {
		t.Fatal("malformed version → expected error, got nil")
	}
	if !strings.Contains(err.Error(), AmendmentsFileName) {
		t.Errorf("error %q should name the file", err.Error())
	}
	if !strings.Contains(err.Error(), "14-digit") {
		t.Errorf("error %q should hint the format", err.Error())
	}
}

// CircumventVersions = file ∪ env (§7: env is a local-dev override).
func TestCircumventVersions_Union(t *testing.T) {
	dir := writeAmendments(t, "20260521112759\tv2026.06.1\tcrash-fix\n")
	t.Setenv(CircumventEnvVar, "20260522080000")
	got, err := CircumventVersions(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !got[20260521112759] {
		t.Errorf("file version missing from union: %v", got)
	}
	if !got[20260522080000] {
		t.Errorf("env version missing from union: %v", got)
	}
	if len(got) != 2 {
		t.Errorf("expected 2 (file ∪ env), got %d (%v)", len(got), got)
	}
}

// Production shape: env unset → the committed file is the sole source.
func TestCircumventVersions_FileOnly_NoEnv(t *testing.T) {
	dir := writeAmendments(t, "20260521112759\tv2026.06.1\tcrash-fix\n")
	t.Setenv(CircumventEnvVar, "")
	got, err := CircumventVersions(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || !got[20260521112759] {
		t.Errorf("expected only the file's version, got %v", got)
	}
}

// A malformed env override still fails loudly through the union path.
func TestCircumventVersions_EnvMalformed_Loud(t *testing.T) {
	dir := writeAmendments(t, "20260521112759\tv1\tok\n")
	t.Setenv(CircumventEnvVar, "garbage")
	if _, err := CircumventVersions(dir); err == nil {
		t.Fatal("malformed env → expected error, got nil")
	}
}

// No file AND no env → empty set, no error (the universal default).
func TestCircumventVersions_Neither(t *testing.T) {
	t.Setenv(CircumventEnvVar, "")
	got, err := CircumventVersions(t.TempDir())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty set, got %v", got)
	}
}
