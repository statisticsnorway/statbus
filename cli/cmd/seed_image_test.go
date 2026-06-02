package cmd

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// dockerAvailable reports whether a usable docker daemon is reachable.
// Tests that build/extract images skip when it is not (CI without docker,
// laptops with the daemon stopped) rather than failing.
func dockerAvailable() bool {
	if _, err := exec.LookPath("docker"); err != nil {
		return false
	}
	return exec.Command("docker", "info").Run() == nil
}

// TestExtractSeedFromImage builds a trivial `FROM scratch` image carrying
// exactly /seed.pg_dump + /seed.json — the two files the real seed stage
// ships (postgres/Dockerfile:521-529) — and asserts extractSeedFromImage
// docker-cp's both out byte-for-byte and that loadSeedMeta parses the
// result. This exercises the scratch-image extraction path (docker create
// + docker cp + docker rm) that replaced the git-branch fetch in #15.
func TestExtractSeedFromImage(t *testing.T) {
	if !dockerAvailable() {
		t.Skip("docker daemon not available")
	}

	tmp := t.TempDir()
	ctx := filepath.Join(tmp, "ctx")
	if err := os.MkdirAll(ctx, 0o755); err != nil {
		t.Fatal(err)
	}

	// Binary content including a NUL and a high byte — proves docker cp is
	// binary-safe (the old gitShowToFile streamed bytes for the same reason;
	// a string round-trip would have corrupted the pg_dump custom format).
	dumpBytes := []byte("PGDMP\x00\x01\x02fake-custom-format\xff\xfe")
	metaJSON := []byte(`{"migration_version":"20260602070530","post_restore_sha":"abc123","commit_sha":"deadbeefdeadbeef","tags":"","created_at":"2026-06-02T00:00:00Z"}`)
	if err := os.WriteFile(filepath.Join(ctx, "seed.pg_dump"), dumpBytes, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(ctx, "seed.json"), metaJSON, 0o644); err != nil {
		t.Fatal(err)
	}
	dockerfile := "FROM scratch\nCOPY seed.pg_dump /seed.pg_dump\nCOPY seed.json /seed.json\n"
	if err := os.WriteFile(filepath.Join(ctx, "Dockerfile"), []byte(dockerfile), 0o644); err != nil {
		t.Fatal(err)
	}

	imageRef := fmt.Sprintf("statbus-seed-extract-unittest:%d", os.Getpid())
	if out, err := exec.Command("docker", "build", "-t", imageRef, ctx).CombinedOutput(); err != nil {
		t.Fatalf("docker build test seed image: %v\n%s", err, out)
	}
	defer exec.Command("docker", "rmi", "-f", imageRef).Run()

	seedDir := filepath.Join(tmp, ".db-seed")
	if err := os.MkdirAll(seedDir, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := extractSeedFromImage(tmp, imageRef, seedDir); err != nil {
		t.Fatalf("extractSeedFromImage: %v", err)
	}

	gotDump, err := os.ReadFile(filepath.Join(seedDir, "seed.pg_dump"))
	if err != nil {
		t.Fatalf("read extracted seed.pg_dump: %v", err)
	}
	if !bytes.Equal(gotDump, dumpBytes) {
		t.Fatalf("seed.pg_dump corrupted in transit: got %d bytes, want %d (binary-safety regression)", len(gotDump), len(dumpBytes))
	}

	meta, err := loadSeedMeta(tmp)
	if err != nil {
		t.Fatalf("loadSeedMeta after extraction: %v", err)
	}
	if meta.MigrationVersion != "20260602070530" {
		t.Fatalf("migration_version = %q, want 20260602070530", meta.MigrationVersion)
	}

	// Negative path: a non-existent image whose registry will not resolve
	// (.invalid is reserved, RFC 2606 → fast NXDOMAIN) → docker create fails
	// → extractSeedFromImage returns an error. This is what makes `./sb db
	// seed fetch` soft-fail so install/dev fall back to running migrations.
	if err := extractSeedFromImage(tmp, "statbus-seed-absent.invalid/nope:0", seedDir); err == nil {
		t.Fatal("extractSeedFromImage on a non-existent image: expected an error, got nil")
	}
}

// TestResolveSeedCommitShort covers the tag-resolution contract: prefer
// COMMIT_SHORT from .env, never return the `local` dev sentinel as a tag,
// and yield "" when nothing resolves (so fetch soft-fails into migrate-up).
func TestResolveSeedCommitShort(t *testing.T) {
	// COMMIT_SHORT present in the generated .env → returned verbatim.
	tmp := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmp, ".env"), []byte("COMMIT_SHORT=abcd1234\nOTHER=x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := resolveSeedCommitShort(tmp); got != "abcd1234" {
		t.Fatalf("resolveSeedCommitShort with COMMIT_SHORT=abcd1234 = %q, want abcd1234", got)
	}

	// COMMIT_SHORT=local (compose's `${COMMIT_SHORT:-local}` dev default) is
	// NOT a published tag and must never be used as one. With no git repo in
	// the temp dir the git fallback yields "" → fetch soft-fails.
	tmp2 := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmp2, ".env"), []byte("COMMIT_SHORT=local\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := resolveSeedCommitShort(tmp2); got == "local" {
		t.Fatalf("resolveSeedCommitShort must never return the 'local' sentinel as a tag; got %q", got)
	}
}
