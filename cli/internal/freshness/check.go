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
//
// Recovery primitive: when a `selfheal=true` command (install, upgrade
// service, upgrade apply-latest) hits the staleness case, RebuildAndReexec
// (sibling file rebuild.go) handles the rebuild + re-exec dance.
// Detection (this file) is decoupled from recovery (rebuild.go); IsStale
// stays a pure read.
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
// otherwise — covering committed-drift, uncommitted-drift, the
// combined case, AND broken-freshness-check states the operator
// should know about.
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
// Drift classification (two independent probes):
//
//   - **committedDrift**: `git diff --quiet <commitSHA> HEAD -- cli/`
//     exit 1. The binary was built from a commit older (or different)
//     than HEAD, AND cli/ has commits between them. Skipped entirely
//     when commitSHA == HEAD (no possible drift between identical
//     commits). Operator action: rebuild the binary from HEAD.
//
//   - **uncommittedDrift**: `git diff --quiet HEAD -- cli/` exit 1.
//     The worktree has uncommitted cli/ changes (staged or unstaged)
//     vs HEAD. Operator action: commit those changes, then rebuild;
//     or rebuild from the WIP tree if iterating.
//
// The four classification outcomes:
//   - neither → "" (fresh)
//   - committed only → "built from X, HEAD is now Y" message
//   - uncommitted only → "built from X (matches HEAD), but cli/ has
//     uncommitted changes" — the case King hit while iterating, where
//     the prior monolithic message misled by suggesting a rebuild
//     without naming the actual root cause (staged changes).
//   - both → message names both drifts.
//
// Rebuild remediation always lists BOTH build paths:
//   - `./dev.sh build-sb` — host-platform only, fast (~3s).
//     Daily-driver / dev iteration.
//   - `./dev.sh cross-build-sb` — all four target platforms.
//     Release artifact production.
//
// Diagnostic returns for environment failures (non-empty):
//   - exec failure (git not installed, fork failed, permission
//     denied) → freshness-check-could-not-run diagnostic.
//   - non-1 exit (typically 128 = bad revision: build commit
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

	// Resolve HEAD to determine whether the binary is at HEAD or a
	// different commit. Same-commit case skips the committed-drift
	// probe entirely (diff against self is empty, no point spending
	// the syscall + opening a bad-revision failure mode).
	headCmd := exec.Command("git", "rev-parse", "HEAD")
	headCmd.Dir = projDir
	var headStderr bytes.Buffer
	headCmd.Stderr = &headStderr
	headOut, err := headCmd.Output()
	if err != nil {
		if _, ok := err.(*exec.ExitError); !ok {
			return fmt.Sprintf(
				"freshness check could not run git: %v.\n"+
					"  Investigate the git environment (PATH, install, permissions), then retry.",
				err)
		}
		// rev-parse HEAD failed (no HEAD? bare repo?). Surface it.
		stderrMsg := strings.TrimSpace(headStderr.String())
		if len(stderrMsg) > 200 {
			stderrMsg = stderrMsg[:200] + "..."
		}
		return fmt.Sprintf(
			"freshness check failed: `git rev-parse HEAD` failed.\n"+
				"  stderr: %s\n"+
				"  Confirm the worktree at %s is a valid git checkout with a HEAD.",
			stderrMsg, projDir)
	}
	headFull := strings.TrimSpace(string(headOut))
	headShort := headFull
	if len(headShort) > 8 {
		headShort = headShort[:8]
	}

	committedDrift, msg := probeCommittedDrift(projDir, commitSHA, headFull, short)
	if msg != "" {
		return msg
	}

	uncommittedDrift, msg := probeUncommittedDrift(projDir)
	if msg != "" {
		return msg
	}

	rebuildHint := "  Rebuild:\n" +
		"    ./dev.sh build-sb       (host-only, fast — for dev iteration)\n" +
		"    ./dev.sh cross-build-sb (all platforms — for release artifacts)"

	switch {
	case !committedDrift && !uncommittedDrift:
		return ""
	case committedDrift && !uncommittedDrift:
		return fmt.Sprintf(
			"./sb is stale: built from %s, HEAD is now %s with cli/ changes.\n%s",
			short, headShort, rebuildHint)
	case !committedDrift && uncommittedDrift:
		return fmt.Sprintf(
			"./sb is stale: built from %s (matches HEAD), but cli/ has uncommitted changes.\n"+
				"  Commit them and rebuild, OR rebuild to include the WIP state:\n"+
				"    ./dev.sh build-sb       (host-only, fast — for dev iteration)\n"+
				"    ./dev.sh cross-build-sb (all platforms — for release artifacts)",
			short)
	default: // both
		return fmt.Sprintf(
			"./sb is stale: built from %s, HEAD is now %s with cli/ changes, AND cli/ has uncommitted changes.\n"+
				"  Commit (or stash) uncommitted changes, then rebuild:\n"+
				"    ./dev.sh build-sb       (host-only, fast — for dev iteration)\n"+
				"    ./dev.sh cross-build-sb (all platforms — for release artifacts)",
			short, headShort)
	}
}

// probeCommittedDrift runs `git diff --quiet <commitSHA> HEAD -- cli/`
// to detect cli/ changes BETWEEN the binary's commit and HEAD.
// Returns (drift, errorMsg) — errorMsg non-empty means the probe
// itself failed and callers should propagate it instead of any drift
// flag.
//
// Skips entirely when commitSHA prefixes (or is prefixed by) the
// full HEAD SHA — same commit, no possible committed-drift, no
// syscall.
func probeCommittedDrift(projDir, commitSHA, headFull, short string) (bool, string) {
	if strings.HasPrefix(headFull, commitSHA) || strings.HasPrefix(commitSHA, headFull) {
		return false, ""
	}
	cmd := exec.Command("git", "diff", "--quiet", commitSHA, headFull, "--", "cli/")
	cmd.Dir = projDir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		return false, ""
	}
	exitErr, ok := err.(*exec.ExitError)
	if !ok {
		return false, fmt.Sprintf(
			"freshness check could not run git: %v.\n"+
				"  Investigate the git environment (PATH, install, permissions), then retry.",
			err)
	}
	if exitErr.ExitCode() == 1 {
		return true, ""
	}
	// Other exit codes — typically 128 ("fatal: bad revision" when
	// the build commit isn't in the local repo).
	stderrMsg := strings.TrimSpace(stderr.String())
	if len(stderrMsg) > 200 {
		stderrMsg = stderrMsg[:200] + "..."
	}
	return false, fmt.Sprintf(
		"freshness check failed: `git diff` exited %d.\n"+
			"  stderr: %s\n"+
			"  This usually means the build commit (%s) isn't in the local repo —\n"+
			"  rebuild from a tree that resolves it, or `git fetch` to retrieve it.",
		exitErr.ExitCode(), stderrMsg, short)
}

// probeUncommittedDrift runs `git diff --quiet HEAD -- cli/` to
// detect uncommitted (staged or unstaged) cli/ changes vs HEAD.
// `git diff HEAD` covers BOTH staged and unstaged uncommitted changes
// because the working tree is the union of both relative to HEAD.
//
// Returns (drift, errorMsg) — errorMsg non-empty means the probe
// itself failed.
func probeUncommittedDrift(projDir string) (bool, string) {
	cmd := exec.Command("git", "diff", "--quiet", "HEAD", "--", "cli/")
	cmd.Dir = projDir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		return false, ""
	}
	exitErr, ok := err.(*exec.ExitError)
	if !ok {
		return false, fmt.Sprintf(
			"freshness check could not run git: %v.\n"+
				"  Investigate the git environment (PATH, install, permissions), then retry.",
			err)
	}
	if exitErr.ExitCode() == 1 {
		return true, ""
	}
	stderrMsg := strings.TrimSpace(stderr.String())
	if len(stderrMsg) > 200 {
		stderrMsg = stderrMsg[:200] + "..."
	}
	return false, fmt.Sprintf(
		"freshness check failed: `git diff HEAD -- cli/` exited %d.\n"+
			"  stderr: %s",
		exitErr.ExitCode(), stderrMsg)
}
