package freshness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

// SelfHealAttemptEnv is the env-var name set on the child process after a
// rebuild + re-exec. stalenessGuard checks for it on the next pass — if
// freshness STILL fails inside a child marked with this var, we exit 2
// rather than recurse. Single-attempt guard is enough: rebuild either
// produces a binary matching HEAD or doesn't, and looping won't help.
const SelfHealAttemptEnv = "_SB_SELFHEAL_ATTEMPT"

// RebuildAndReexec runs `make -C cli build` from projDir, then exec's
// the just-built ./sb with the original argv and a child env carrying
// SelfHealAttemptEnv=1. The exec replaces this process — on success
// this function does not return.
//
// Returns an error only when:
//   - the build fails (non-zero exit, or 5-minute timeout); or
//   - syscall.Exec fails (rare: ENOEXEC on a corrupted just-built
//     binary, EACCES on a perm bug).
//
// 5-minute build budget matches Service.buildBinaryOnDisk in the upgrade
// pipeline; cold-cache cgo-disabled go build is ~30s typical.
//
// Callers (currently only stalenessGuard for self-heal-annotated
// commands) are responsible for guarding against recursion via
// SelfHealAttemptEnv. This function does not check it itself — that
// would couple the rebuild primitive to the staleness-check policy.
func RebuildAndReexec(projDir string) error {
	cmd := exec.Command("make", "-C", "cli", "build")
	cmd.Dir = projDir
	// Build logs to stderr so the calling process's stdout stays
	// uncluttered. The operator sees compile output as it streams.
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()

	done := make(chan error, 1)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start `make -C cli build`: %w", err)
	}
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		if err != nil {
			return fmt.Errorf("rebuild failed: %w", err)
		}
	case <-time.After(5 * time.Minute):
		_ = cmd.Process.Kill()
		return fmt.Errorf("rebuild timed out after 5m")
	}

	sbPath := filepath.Join(projDir, "sb")
	env := append(os.Environ(), SelfHealAttemptEnv+"=1")
	return syscall.Exec(sbPath, os.Args, env)
}
