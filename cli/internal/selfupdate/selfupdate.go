// Package selfupdate handles binary self-replacement with rollback.
package selfupdate

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

// Update downloads a new binary, verifies its checksum, and replaces the current one.
// Returns (swapped, err). The caller should exit with code 42 for systemd restart
// regardless of swapped — the restart is the handoff to whatever is on disk.
//
// Idempotency shortcut: if the file at currentPath already hashes to the
// expected SHA-256, Update is a no-op (no download, no rename) and returns
// swapped=false. This lets the end-of-flow self-update call from the
// upgrade service be harmless when an earlier step in the flow
// (replaceBinaryOnDisk before migrations) has already swapped the binary,
// and lets the caller pick an honest log phrasing ("already at target"
// vs "Self-updating binary...").
//
// expectCommit is the upgrade target's commit SHA; it is forwarded to the
// self-verify subprocess (see ReplaceBinaryOnDisk) so the freshly-written binary
// asserts it IS the target — never against the worktree, which STATBUS-060 leaves
// at the source mid-upgrade. Empty means "boot-only self-verify" (legacy callers).
func Update(currentPath, downloadURL, expectedSHA256, expectCommit string) (swapped bool, err error) {
	if match, _ := sha256Match(currentPath, expectedSHA256); match {
		return false, nil
	}
	if err := ReplaceBinaryOnDisk(currentPath, downloadURL, expectedSHA256, expectCommit); err != nil {
		return false, err
	}
	return true, nil
}

// ReplaceBinaryOnDisk downloads the binary, verifies SHA-256, self-verifies
// by invoking `upgrade self-verify` on the freshly-downloaded file, and then
// atomically swaps it in: renames the current binary to <path>.old and the
// new one into place.
//
// Unlike Update, this always performs the download+swap even if the current
// file already matches — callers use it as the explicit "swap now" primitive
// (e.g. upgrade service's mid-flow swap between git-checkout and migrate).
//
// expectCommit (STATBUS-171) is the upgrade target's commit SHA. When non-empty
// it is passed to `upgrade self-verify --expect-commit`, so the freshly-written
// binary asserts its OWN embedded commit equals the target — the fact this step
// exists to check. The self-verify is guard-exempt (freshness_probe): a
// worktree-relative staleness check there is a category error, because
// STATBUS-060 deliberately leaves the worktree at the SOURCE commit during the
// swap, so a target binary would ALWAYS (correctly, per that contract) be judged
// "stale" and abort. Empty expectCommit means boot-only self-verify (legacy).
func ReplaceBinaryOnDisk(currentPath, downloadURL, expectedSHA256, expectCommit string) error {
	newPath := currentPath + ".new"
	oldPath := currentPath + ".old"

	// Step 1: Download new binary (with timeout to prevent hanging on slow connections)
	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Get(downloadURL)
	if err != nil {
		return fmt.Errorf("download: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download returned HTTP %d", resp.StatusCode)
	}

	out, err := os.Create(newPath)
	if err != nil {
		return fmt.Errorf("create temp file: %w", err)
	}

	h := sha256.New()
	if _, err := io.Copy(io.MultiWriter(out, h), resp.Body); err != nil {
		_ = out.Close()
		_ = os.Remove(newPath) // best-effort cleanup of the partial download
		return fmt.Errorf("write: %w", err)
	}
	_ = out.Close()

	// Step 2: Verify SHA256
	actual := hex.EncodeToString(h.Sum(nil))
	if actual != expectedSHA256 {
		_ = os.Remove(newPath) // best-effort cleanup of the bad download
		return fmt.Errorf("checksum mismatch: got %s, want %s", actual, expectedSHA256)
	}

	// Step 3: Make executable
	if err := os.Chmod(newPath, 0755); err != nil {
		_ = os.Remove(newPath) // best-effort cleanup
		return fmt.Errorf("chmod: %w", err)
	}

	// Step 3b: Verify the new binary can boot AND is the intended target
	// (STATBUS-171). --expect-commit makes self-verify assert its embedded commit
	// equals the upgrade target, rather than run the worktree-relative
	// stalenessGuard (a category error mid-upgrade under STATBUS-060's deferred
	// checkout — see this function's doc comment).
	verifyArgs := []string{"upgrade", "self-verify"}
	if expectCommit != "" {
		verifyArgs = append(verifyArgs, "--expect-commit", expectCommit)
	}
	cmd := exec.Command(newPath, verifyArgs...)
	cmd.Dir = filepath.Dir(currentPath)
	if out, err := cmd.CombinedOutput(); err != nil {
		_ = os.Remove(newPath) // best-effort cleanup of the unverified binary
		return fmt.Errorf("self-verify failed: %w\n%s", err, string(out))
	}

	// Step 4: Keep old as rollback
	_ = os.Remove(oldPath) // ignore error — might not exist
	if err := os.Rename(currentPath, oldPath); err != nil {
		_ = os.Remove(newPath) // best-effort cleanup
		return fmt.Errorf("backup current binary: %w", err)
	}

	// Step 5: Atomic replace
	if err := os.Rename(newPath, currentPath); err != nil {
		// Try to restore old binary — best-effort: if this ALSO fails, the
		// original "replace binary" error below is still the right one to
		// surface; there is nothing better to do mid-catastrophe.
		_ = os.Rename(oldPath, currentPath)
		return fmt.Errorf("replace binary: %w", err)
	}

	return nil
}

// sha256Match returns true if the file at path hashes to expectedHex.
// Returns (false, err) if the file cannot be opened or read.
func sha256Match(path, expectedHex string) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer func() { _ = f.Close() }()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return false, err
	}
	return hex.EncodeToString(h.Sum(nil)) == expectedHex, nil
}

// Rollback restores the previous binary from .old.
func Rollback(currentPath string) error {
	oldPath := currentPath + ".old"
	if _, err := os.Stat(oldPath); os.IsNotExist(err) {
		return fmt.Errorf("no rollback binary found at %s", oldPath)
	}
	return os.Rename(oldPath, currentPath)
}

// CleanOld removes the .old backup after a successful self-update.
func CleanOld(currentPath string) {
	_ = os.Remove(currentPath + ".old") // best-effort; a leftover .old is harmless
}

// Platform returns the platform identifier for binary downloads.
func Platform() string {
	return runtime.GOOS + "-" + runtime.GOARCH
}
