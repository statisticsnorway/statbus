package freshness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/statisticsnorway/statbus/cli/internal/sbimage"
)

// SelfHealAttemptEnv is the env-var name set on the child process after a
// rebuild + re-exec. stalenessGuard checks for it on the next pass — if
// freshness STILL fails inside a child marked with this var, we exit 2
// rather than recurse. Single-attempt guard is enough: rebuild either
// produces a binary matching HEAD or doesn't, and looping won't help.
const SelfHealAttemptEnv = "_SB_SELFHEAL_ATTEMPT"

// RebuildAndReexec procures a fresh ./sb matching the worktree HEAD and exec's
// it with the original argv and a child env carrying SelfHealAttemptEnv=1. The
// exec replaces this process — on success this function does not return.
//
// The binary is stale relative to the worktree's cli/ tree, so the target is
// the worktree HEAD. Procurement is TOOLCHAIN-FREE (sbimage.Procure): pull the
// commit-tagged statbus-sb image, or — for an UNPUSHED local HEAD — build it
// in-container via cli/Dockerfile.sb (golang runs inside Docker; no host
// Go/make). This is the fix for the no-host-Go failure mode: the old
// implementation ran `make -C cli build`, which fails with `make: go: command
// not found` (exit 2) on SSB standalone boxes and every install-recovery VM.
//
// Returns an error only when:
//   - HEAD cannot be resolved; or
//   - procurement fails (pull miss with no buildable target, build failure,
//     docker create/cp failure, timeout); or
//   - syscall.Exec fails (rare: ENOEXEC on a corrupt binary, EACCES).
//
// Callers (currently only stalenessGuard for self-heal-annotated commands) are
// responsible for guarding against recursion via SelfHealAttemptEnv. This
// function does not check it itself — that would couple the procurement
// primitive to the staleness-check policy.
func RebuildAndReexec(projDir string) error {
	head, err := headCommit(projDir)
	if err != nil {
		return fmt.Errorf("resolve worktree HEAD for self-heal procurement: %w", err)
	}

	sbPath := filepath.Join(projDir, "sb")
	if err := sbimage.Procure(projDir, head, sbPath); err != nil {
		return fmt.Errorf("self-heal procure failed: %w", err)
	}

	env := append(os.Environ(), SelfHealAttemptEnv+"=1")
	return syscall.Exec(sbPath, os.Args, env)
}

// headCommit returns the worktree HEAD commit SHA. log.showSignature is
// disabled for the invocation so a globally-configured commit-signature banner
// cannot prepend "Good 'git' signature..." lines to rev-parse output.
func headCommit(projDir string) (string, error) {
	cmd := exec.Command("git", "-c", "log.showSignature=false", "rev-parse", "HEAD")
	cmd.Dir = projDir
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	head := strings.TrimSpace(string(out))
	if head == "" {
		return "", fmt.Errorf("git rev-parse HEAD returned empty output in %s", projDir)
	}
	return head, nil
}
