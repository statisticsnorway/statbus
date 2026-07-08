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

// CommittedDrift reports whether the binary built from commitSHA differs from
// the worktree's HEAD with cli/ changes between them — the committed-drift axis
// ONLY (not uncommitted/WIP drift, which a rebuild can't clear and which only a
// file-mtime check can detect). This is the signal a rebuild decision needs
// that file mtimes miss: `git commit`/`checkout`/`pull` move HEAD without
// touching working-tree mtimes. A binary built from an older commit answers
// reliably — its build commit is baked in at link time; HEAD is read live.
//
//	(true,  nil) committed drift — rebuild to HEAD.
//	(false, nil) no committed drift (binary at HEAD, or no cli/ delta between).
//	(false, err) probe could not run (no identity / not a git tree / git error);
//	             the caller (dev.sh) treats this as "rebuild" to stay safe.
//
// Deliberately NOT a wrapper that also reports uncommitted drift: triggering a
// rebuild on a dirty tree would loop (the tree stays dirty after the rebuild).
func CommittedDrift(projDir, commitSHA string) (bool, error) {
	if commitSHA == "" || commitSHA == "unknown" {
		return false, fmt.Errorf("binary has no reliable commit identity (built without ldflags)")
	}
	if _, err := os.Stat(filepath.Join(projDir, ".git")); err != nil {
		return false, fmt.Errorf("%s is not a git checkout (no .git): %w", projDir, err)
	}
	headCmd := exec.Command("git", "rev-parse", "HEAD")
	headCmd.Dir = projDir
	out, err := headCmd.Output()
	if err != nil {
		return false, fmt.Errorf("git rev-parse HEAD failed: %w", err)
	}
	headFull := strings.TrimSpace(string(out))
	short := commitSHA
	if len(short) > 8 {
		short = short[:8]
	}
	drift, errMsg := probeCommittedDrift(projDir, commitSHA, headFull, short)
	if errMsg != "" {
		return false, fmt.Errorf("%s", errMsg)
	}
	return drift, nil
}

// IsStale returns "" when the binary's build commit matches HEAD's
// cli/ tree (no committed drift), and a human-readable diagnostic
// otherwise — committed drift, plus broken-freshness-check states the
// operator should know about. Uncommitted (WIP) cli/ edits are NOT
// flagged: the guard can't tell whether they're in the binary, so it
// reports only what it can verify (the build commit vs HEAD).
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
// Committed-drift classification:
//
//   - **committedDrift**: `git diff --quiet <commitSHA> HEAD -- cli/`
//     exit 1. The binary was built from a commit older (or different)
//     than HEAD, AND cli/ has commits between them. Skipped entirely
//     when commitSHA == HEAD (no possible drift between identical
//     commits). Operator action: rebuild the binary from HEAD.
//
// Outcomes:
//   - no committed drift → "" (fresh) — including a dirty worktree on a
//     HEAD-matching binary: WIP edits are intentionally not flagged
//     (see CommittedDrift's rationale).
//   - committed drift → "built from X, HEAD is now Y" message.
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

	// Committed drift is the only staleness the guard can reliably assert: the
	// binary's build commit differs from HEAD with cli/ changes between. We do
	// NOT flag uncommitted (WIP) cli/ edits — the binary's identity is
	// commit-based, blind to whether it was built from the current uncommitted
	// bytes, so a "dirty tree" verdict would be a guess (and a false positive
	// whenever the binary was just rebuilt from that WIP tree). Treating WIP as
	// fresh lets you run ./sb while editing cli/; the real upgrade-safety hazard
	// — pulled new code, didn't rebuild — is committed drift, which stays.
	if !committedDrift {
		return ""
	}
	return fmt.Sprintf(
		"./sb is stale: built from %s, HEAD is now %s with cli/ changes.\n"+
			"  Refresh ./sb — no host toolchain needed (procures the HEAD-matching binary\n"+
			"  from the commit-tagged image, then re-execs):\n"+
			"    ./sb install\n"+
			"  (dev box with a Go toolchain: ./dev.sh build-sb, or ./dev.sh cross-build-sb for all platforms)",
		short, headShort)
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
