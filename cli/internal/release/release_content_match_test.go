package release

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// sha256Hex mirrors migrate.sha256File: hex(sha256(raw bytes)). The recognition
// function compares blob hashes against a stored db.migration.content_hash, so
// the test computes its expectations exactly the same way.
func sha256Hex(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// gitIn runs a git command in dir, failing the test on error.
func gitIn(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v (in %s): %v\n%s", args, dir, err, out)
	}
}

// TestReleaseTagWithMigrationHash_ShallowClone builds a real origin with two
// release tags carrying DIFFERENT bytes for the same migration version, makes an
// actual `git clone --depth 1 --no-tags` (the deployed-box shape: shallow, no
// local tag trees), and proves content-level recognition works there
// (STATBUS-166 AC#1 shallow-clone proof + AC#2 unvetted-refuse, at the
// recognition level): vetted bytes resolve to the release that carries them;
// unvetted bytes and unreleased versions resolve to "".
func TestReleaseTagWithMigrationHash_ShallowClone(t *testing.T) {
	const version = 20260218215337
	b1 := []byte("-- v1 (shipped in v2026.02.1)\nSELECT 1;\n")
	b2 := []byte("-- v2 broken-fix (blessed in v2026.03.1-rc.1)\nSELECT 2;\n")
	b3 := []byte("-- v3 ungated local edit, in NO release\nSELECT 3;\n")

	origin := t.TempDir()
	gitIn(t, origin, "init", "-q")
	gitIn(t, origin, "config", "user.email", "test@example.com")
	gitIn(t, origin, "config", "user.name", "test")
	rel := filepath.Join("migrations", "20260218215337_desc.up.sql")
	full := filepath.Join(origin, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	writeCommitTag := func(content []byte, tag string) {
		if err := os.WriteFile(full, content, 0o644); err != nil {
			t.Fatal(err)
		}
		gitIn(t, origin, "add", rel)
		gitIn(t, origin, "commit", "-q", "-m", tag)
		gitIn(t, origin, "tag", tag)
	}
	writeCommitTag(b1, "v2026.02.1")      // stable carrying b1
	writeCommitTag(b2, "v2026.03.1-rc.1") // newer RC carrying the blessed b2

	// The deployed-box shape: shallow AND no local tags — so the recognition
	// function must reach the remote (git ls-remote) and fetch each tag's tree.
	parent := t.TempDir()
	box := filepath.Join(parent, "box")
	gitIn(t, parent, "clone", "--depth", "1", "--no-tags", "file://"+origin, "box")

	// Sanity: the clone really is shallow (otherwise the test proves nothing
	// about the shallow-clone hard requirement).
	out, err := exec.Command("git", "-C", box, "rev-parse", "--is-shallow-repository").Output()
	if err != nil || strings.TrimSpace(string(out)) != "true" {
		t.Fatalf("test setup: box is not a shallow clone (got %q, err %v)", strings.TrimSpace(string(out)), err)
	}

	cases := []struct {
		name    string
		version int64
		hash    string
		wantTag string
	}{
		{"vetted bytes (newest RC) → its tag", version, sha256Hex(b2), "v2026.03.1-rc.1"},
		{"older-release bytes → the older tag", version, sha256Hex(b1), "v2026.02.1"},
		{"ungated edit, bytes in no release → refuse", version, sha256Hex(b3), ""},
		{"version in no release at all → refuse", 20990101000000, sha256Hex(b2), ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ReleaseTagWithMigrationHash(box, tc.version, tc.hash)
			if err != nil {
				t.Fatalf("ReleaseTagWithMigrationHash: %v", err)
			}
			if got != tc.wantTag {
				t.Errorf("got tag %q, want %q", got, tc.wantTag)
			}
		})
	}
}

// TestReleaseTagLess_NewestFirstOrdering pins the CalVer ordering the recognition
// scan relies on for its single-fetch common case: a final release is newer than
// its -rc.N, multi-digit patch/rc compare numerically (not lexically), and the
// newest tag sorts first.
func TestReleaseTagLess_NewestFirstOrdering(t *testing.T) {
	// ascending (oldest → newest)
	ordered := []string{
		"v2026.02.9",
		"v2026.02.10", // 10 > 9 numerically, not lexically
		"v2026.03.1-rc.2",
		"v2026.03.1-rc.10", // 10 > 2 numerically
		"v2026.03.1",       // final release newer than all its rc's
		"v2027.01.1",
	}
	for i := 0; i+1 < len(ordered); i++ {
		if !releaseTagLess(ordered[i], ordered[i+1]) {
			t.Errorf("expected %q < %q (older), but releaseTagLess said no", ordered[i], ordered[i+1])
		}
		if releaseTagLess(ordered[i+1], ordered[i]) {
			t.Errorf("expected %q not-< %q, but releaseTagLess said yes", ordered[i+1], ordered[i])
		}
	}
}
