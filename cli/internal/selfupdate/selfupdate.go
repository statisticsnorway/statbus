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
// Returns nil on success. The caller should exit with code 42 for systemd restart.
func Update(currentPath, downloadURL, expectedSHA256 string) error {
	newPath := currentPath + ".new"
	oldPath := currentPath + ".old"

	// Step 1: Download new binary (with timeout to prevent hanging on slow connections)
	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Get(downloadURL)
	if err != nil {
		return fmt.Errorf("download: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download returned HTTP %d", resp.StatusCode)
	}

	out, err := os.Create(newPath)
	if err != nil {
		return fmt.Errorf("create temp file: %w", err)
	}

	h := sha256.New()
	if _, err := io.Copy(io.MultiWriter(out, h), resp.Body); err != nil {
		out.Close()
		os.Remove(newPath)
		return fmt.Errorf("write: %w", err)
	}
	out.Close()

	// Step 2: Verify SHA256
	actual := hex.EncodeToString(h.Sum(nil))
	if actual != expectedSHA256 {
		os.Remove(newPath)
		return fmt.Errorf("checksum mismatch: got %s, want %s", actual, expectedSHA256)
	}

	// Step 3: Make executable
	if err := os.Chmod(newPath, 0755); err != nil {
		os.Remove(newPath)
		return fmt.Errorf("chmod: %w", err)
	}

	// Step 3b: Verify the new binary can boot (self-verify)
	cmd := exec.Command(newPath, "upgrade", "self-verify")
	cmd.Dir = filepath.Dir(currentPath)
	if out, err := cmd.CombinedOutput(); err != nil {
		os.Remove(newPath)
		return fmt.Errorf("self-verify failed: %w\n%s", err, string(out))
	}

	// Step 4: Keep old as rollback
	os.Remove(oldPath) // ignore error — might not exist
	if err := os.Rename(currentPath, oldPath); err != nil {
		os.Remove(newPath)
		return fmt.Errorf("backup current binary: %w", err)
	}

	// Step 5: Atomic replace
	if err := os.Rename(newPath, currentPath); err != nil {
		// Try to restore old binary
		os.Rename(oldPath, currentPath)
		return fmt.Errorf("replace binary: %w", err)
	}

	return nil
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
	os.Remove(currentPath + ".old")
}

// Platform returns the platform identifier for binary downloads.
func Platform() string {
	return runtime.GOOS + "-" + runtime.GOARCH
}
