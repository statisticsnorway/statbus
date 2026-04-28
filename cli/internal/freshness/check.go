// Package freshness detects whether the running ./sb binary is built
// from a commit older than the worktree's cli/ tree. The stale-binary
// foot-gun surfaced during commit 2 verification of plan-rc.66 section
// R: an operator pulls master, runs `./sb migrate up` directly without
// rebuilding, and the migrate runner happily applies migrations using
// pre-pull binary logic — silently divergent from what the just-pulled
// migration files expect.
//
// Cheap structural enforcement at the cobra root: PersistentPreRun
// calls IsStale; if it reports drift, mutating commands hard-fail
// (exit 2) and read-only commands warn-and-proceed.
package freshness

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// IsStale returns "" when the binary's build commit matches the
// worktree's cli/ tree (no drift), and a human-readable diagnostic
// otherwise — covering both stale-binary detection AND broken-
// freshness-check states the operator should know about.
//
// Parameter naming: `commitSHA` mirrors the upgrade table's commit_sha
// column and the `upgrade.CommitSHA` typed value the caller now
// constructs at init (see cli/cmd/root.go resolveCommitSHA). The
// parameter is still typed `string` to keep this leaf package free of
// internal cross-deps; validation happens at the caller's boundary.
//
// Silent skips (return ""):
//   - commitSHA empty or "unknown" — defensive coverage for a caller
//     that hasn't gone through resolveCommitSHA. Today's primary
//     caller (root.go stalenessGuard) refuses such binaries BEFORE
//     reaching this function; the early-return here is belt to that
//     suspenders.
//   - projDir doesn't have a `.git/` directory at its top — tarball
//     install or sparse layout. Without the project's own git repo
//     we can't make the comparison (and git would walk upward to a
//     parent repo, producing false positives).
//
// Diagnostic returns (non-empty):
//   - `git diff --quiet` exit 1 → cli/ tree drifted since build.
//     Stale-binary diagnostic with rebuild remediation.
//   - exec failure (git not installed, fork failed, permission
//     denied) → freshness-check-could-not-run diagnostic.
//   - `git diff` non-1 exit (e.g. 128 = bad revision: build commit
//     missing from local repo, sparse clone, force-rebase) →
//     freshness-check-failed diagnostic naming the exit code +
//     stderr.
//
// Per plan section R commit 5 / fixup: silent skips on non-1 exits
// were a fail-fast violation — they swallowed real environment
// problems and let mutating commands proceed against a broken
// freshness check. PersistentPreRun routes any non-empty return
// through the same hard-fail-on-mutating / warn-on-read-only path,
// so the operator sees and acts on these.
func IsStale(projDir, commitSHA string) string {
	if commitSHA == "" || commitSHA == "unknown" {
		return ""
	}
	// Require .git AT projDir (not somewhere up the tree). Otherwise
	// git's upward search finds the wrong repo and produces false
	// positives. Production tarball installs (no .git) silently skip.
	if _, err := os.Stat(filepath.Join(projDir, ".git")); err != nil {
		return ""
	}

	short := commitSHA
	if len(short) > 8 {
		short = short[:8]
	}

	cmd := exec.Command("git", "diff", "--quiet", commitSHA, "--", "cli/")
	cmd.Dir = projDir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		return ""
	}

	exitErr, ok := err.(*exec.ExitError)
	if !ok {
		// Couldn't run git at all — not installed, fork failed,
		// permission denied, etc.
		return fmt.Sprintf(
			"freshness check could not run git: %v.\n"+
				"  Investigate the git environment (PATH, install, permissions), then retry.",
			err)
	}

	if exitErr.ExitCode() == 1 {
		return fmt.Sprintf(
			"./sb is stale: built from %s, but cli/ has changed since.\n"+
				"  Rebuild: (cd cli && go build -o ../sb .)\n"+
				"  Or run via dev.sh (auto-rebuilds): ./dev.sh <command>",
			short)
	}

	// Other exit codes — typically 128 ("fatal: bad revision" when the
	// build commit isn't in the local repo). Surface the failure rather
	// than silently treating it as fresh; the operator needs to know
	// the freshness check itself is broken.
	stderrMsg := strings.TrimSpace(stderr.String())
	if len(stderrMsg) > 200 {
		stderrMsg = stderrMsg[:200] + "..."
	}
	return fmt.Sprintf(
		"freshness check failed: `git diff` exited %d.\n"+
			"  stderr: %s\n"+
			"  This usually means the build commit (%s) isn't in the local repo —\n"+
			"  rebuild from a tree that resolves it, or `git fetch` to retrieve it.",
		exitErr.ExitCode(),
		stderrMsg,
		short)
}
