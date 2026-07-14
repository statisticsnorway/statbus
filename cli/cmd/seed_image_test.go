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

// TestExtractSeedFromImage builds a trivial busybox:musl image carrying
// exactly /seed.pg_dump + /seed.json — the two files the real seed stage
// ships (postgres/Dockerfile) — and asserts extractSeedFromImage docker-cp's
// both out byte-for-byte and that loadSeedMeta parses the result. busybox
// (vs FROM scratch) carries a default command, so `docker create` works
// without a placeholder arg — mirroring the real self-documenting image.
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
	dockerfile := "FROM busybox:musl\nCOPY seed.pg_dump /seed.pg_dump\nCOPY seed.json /seed.json\n"
	if err := os.WriteFile(filepath.Join(ctx, "Dockerfile"), []byte(dockerfile), 0o644); err != nil {
		t.Fatal(err)
	}

	// Build the test image for linux/amd64 to mirror the REAL published seed image
	// (amd64-only) — extractSeedFromImage pins --platform linux/amd64, so a default
	// (host-arch) build would not match on an arm64 dev box. The Dockerfile only
	// COPYs (no RUN), so this needs no emulation.
	imageRef := fmt.Sprintf("statbus-seed-extract-unittest:%d", os.Getpid())
	if out, err := exec.Command("docker", "build", "--platform", "linux/amd64", "-t", imageRef, ctx).CombinedOutput(); err != nil {
		t.Fatalf("docker build test seed image: %v\n%s", err, out)
	}
	defer func() { _ = exec.Command("docker", "rmi", "-f", imageRef).Run() }()

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

// TestLastContainerID is the Docker-free regression guard for the cold-cache
// cid-contamination bug: RunCommandOutput merges stderr, so a `docker create`
// that PULLS emits its progress ahead of the container id. lastContainerID must
// return the clean id from the last line (never the pull-progress prefix, whose
// first ':' would make `docker cp` report "No such container").
func TestLastContainerID(t *testing.T) {
	const id = "3b40198146dc11ee067d32ae50134cfc17b690af1ed803eb98ea0a445bdb2776"

	// Warm cache: create prints only the id.
	if got, ok := lastContainerID(id + "\n"); !ok || got != id {
		t.Errorf("warm-cache id: got (%q,%v), want (%q,true)", got, ok, id)
	}

	// Cold cache: the exact interleaving observed in the failing oracle run —
	// pull progress (with a ':' in the image ref) precedes the id.
	cold := "Unable to find image 'ghcr.io/statisticsnorway/statbus-seed:c4692562' locally\n" +
		"c4692562: Pulling from statisticsnorway/statbus-seed\n" +
		"bf345c742b44: Pull complete\n" +
		"Digest: sha256:54c57d97d44d1e8172d90f6cf89e1af2882d8cf73e08f7d0dd2b81bbe7615f75\n" +
		"Status: Downloaded newer image for ghcr.io/statisticsnorway/statbus-seed:c4692562\n" +
		id + "\n"
	if got, ok := lastContainerID(cold); !ok || got != id {
		t.Errorf("cold-cache blob: got (%q,%v), want (%q,true) — the pull progress must not leak into the id", got, ok, id)
	}

	// Empty / no-id output → fail loud (false), never a silent empty id.
	for _, bad := range []string{"", "\n\n", "Error: something went wrong\n"} {
		if got, ok := lastContainerID(bad); ok {
			t.Errorf("non-id output %q must yield ok=false; got (%q,true)", bad, got)
		}
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
