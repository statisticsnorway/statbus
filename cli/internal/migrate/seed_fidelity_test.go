package migrate

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-116 (doc-025 rev 2) — unit coverage for the seed-fidelity foundation's
// PURE cores: the ledger content_hash comparator (Parts A/B), the seed-build
// channel routing (Part C detection axis), and the ErrStaleRestoredMigration
// fallback signal (Part C recovery axis). All Docker/DB-free.

// hashOf mirrors sha256File over a literal string (no temp file needed for the
// expected value).
func hashOf(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

// writeUpMigration lays down migrations/<version>_<desc>.up.sql under projDir so
// findUpFile resolves it, and returns the sha256 of its contents.
func writeUpMigration(t *testing.T, projDir string, version int64, body string) string {
	t.Helper()
	dir := filepath.Join(projDir, "migrations")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, fmt.Sprintf("%d_desc.up.sql", version))
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return hashOf(body)
}

// TestLedgerHashMismatchRows is the heart of Parts A & B: given the raw
// "version|content_hash" ledger text, it must flag exactly the rows whose
// recorded hash disagrees with the on-disk file — matching rows produce nothing,
// a stale literal is a mismatch, a NULL sentinel is a mismatch, a file-less
// orphan is skipped (never a mismatch), and malformed rows are skipped.
func TestLedgerHashMismatchRows(t *testing.T) {
	dir := t.TempDir()

	hMatch := writeUpMigration(t, dir, 100, "-- migration 100\nSELECT 1;\n") // stored == live
	writeUpMigration(t, dir, 200, "-- migration 200\nSELECT 2;\n")           // stored is stale
	writeUpMigration(t, dir, 400, "-- migration 400\nSELECT 4;\n")           // stored is <NULL>
	// version 300 has NO file on disk → orphan → skipped.

	rows := fmt.Sprintf(
		"100|%s\n"+ // match
			"200|deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n"+ // stale
			"300|whatever0000000000000000000000000000000000000000000000000000000\n"+ // orphan (no file) → skip
			"400|<NULL>\n"+ // null sentinel → live != "<NULL>" → mismatch
			"garbage-no-pipe\n"+ // malformed → skip
			"notanint|abc\n", // non-numeric version → skip
		hMatch)

	got, err := ledgerHashMismatchRows(dir, rows)
	if err != nil {
		t.Fatalf("ledgerHashMismatchRows returned error: %v", err)
	}

	// Expect exactly versions 200 and 400, in ledger order.
	if len(got) != 2 {
		t.Fatalf("expected 2 mismatches (200, 400), got %d: %+v", len(got), got)
	}
	if got[0].Version != 200 {
		t.Errorf("mismatch[0].Version = %d, want 200", got[0].Version)
	}
	if got[0].StoredHash == got[0].LiveHash {
		t.Errorf("mismatch[0] stored should differ from live; both = %s", got[0].LiveHash)
	}
	if got[1].Version != 400 {
		t.Errorf("mismatch[1].Version = %d, want 400", got[1].Version)
	}
	if got[1].StoredHash != "<NULL>" {
		t.Errorf("mismatch[1].StoredHash = %q, want \"<NULL>\"", got[1].StoredHash)
	}
	// The matching row (100) must never appear.
	for _, m := range got {
		if m.Version == 100 {
			t.Errorf("version 100 matches on disk and must not be flagged: %+v", m)
		}
		if m.Version == 300 {
			t.Errorf("version 300 is a file-less orphan and must be skipped, not flagged: %+v", m)
		}
	}
}

// TestLedgerHashMismatchRows_AllClean: a fully consistent ledger yields no
// mismatches (the DumpSeed publish gate's pass condition).
func TestLedgerHashMismatchRows_AllClean(t *testing.T) {
	dir := t.TempDir()
	h1 := writeUpMigration(t, dir, 111, "one\n")
	h2 := writeUpMigration(t, dir, 222, "two\n")
	rows := fmt.Sprintf("111|%s\n222|%s\n", h1, h2)
	got, err := ledgerHashMismatchRows(dir, rows)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("clean ledger must yield 0 mismatches, got %d: %+v", len(got), got)
	}
}

// TestLedgerHashMismatchRows_Empty: empty/whitespace input is not an error and
// yields nothing (a DB with an empty ledger, or trimmed output).
func TestLedgerHashMismatchRows_Empty(t *testing.T) {
	dir := t.TempDir()
	for _, in := range []string{"", "\n", "   \n  \n"} {
		got, err := ledgerHashMismatchRows(dir, in)
		if err != nil {
			t.Fatalf("empty input %q errored: %v", in, err)
		}
		if len(got) != 0 {
			t.Fatalf("empty input %q yielded %d rows", in, len(got))
		}
	}
}

// TestSeedBuildChannelRouting locks Part C's detection axis: UPGRADE_CHANNEL=
// seed-build classifies channelSeedBuild (so eagerContentHashCheck routes the
// mismatch to ErrStaleRestoredMigration and NEVER to the git-tag probe), while
// the neighbouring channels are unaffected.
func TestSeedBuildChannelRouting(t *testing.T) {
	cases := []struct {
		env  string
		want migrationChannel
	}{
		{"UPGRADE_CHANNEL=seed-build\n", channelSeedBuild},
		{"CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=seed-build\n", channelSeedBuild}, // mode ignored
		{"UPGRADE_CHANNEL=stable\n", channelRelease},                                          // neighbour unaffected
		{"UPGRADE_CHANNEL=local\n", channelLocalDev},
	}
	for _, tc := range cases {
		dir := t.TempDir()
		if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(tc.env), 0o644); err != nil {
			t.Fatal(err)
		}
		if got := migrationChannelClass(dir); got != tc.want {
			t.Errorf("migrationChannelClass(%q) = %d, want %d", tc.env, got, tc.want)
		}
	}
}

// TestErrStaleRestoredMigration_As locks Part C's recovery axis: the sentinel is
// discoverable via errors.As even when wrapped (seed_build.go wraps the migrate
// error), so the caller reliably chooses the full-rebuild fallback. A plain
// wrapped error must NOT match.
func TestErrStaleRestoredMigration_As(t *testing.T) {
	base := &ErrStaleRestoredMigration{Version: 20260218215337, StoredHash: "cd82bc76aa", LiveHash: "71befa0511"}
	wrapped := fmt.Errorf("migrate seed db up: %w", base)

	var got *ErrStaleRestoredMigration
	if !errors.As(wrapped, &got) {
		t.Fatalf("errors.As must find ErrStaleRestoredMigration through one wrap")
	}
	if got.Version != 20260218215337 {
		t.Errorf("recovered Version = %d, want 20260218215337", got.Version)
	}

	// A non-stale wrapped error must not be mistaken for the sentinel.
	other := fmt.Errorf("some other migrate failure: %w", errors.New("boom"))
	var none *ErrStaleRestoredMigration
	if errors.As(other, &none) {
		t.Errorf("errors.As matched an unrelated error as ErrStaleRestoredMigration")
	}

	// Error() names the version and points at the seed-build channel + full rebuild.
	msg := base.Error()
	for _, want := range []string{"20260218215337", "seed-build", "rebuilt full"} {
		if !strings.Contains(msg, want) {
			t.Errorf("Error() = %q, expected to contain %q", msg, want)
		}
	}
}

// TestShortHash: 8-char truncation for logs; short inputs pass through.
func TestShortHash(t *testing.T) {
	if got := shortHash("deadbeefcafe1234"); got != "deadbeef" {
		t.Errorf("shortHash long = %q, want deadbeef", got)
	}
	if got := shortHash("abc"); got != "abc" {
		t.Errorf("shortHash short = %q, want abc", got)
	}
	if got := shortHash(""); got != "" {
		t.Errorf("shortHash empty = %q, want empty", got)
	}
}
