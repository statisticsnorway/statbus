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
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// IsStale returns "" when the binary's build commit matches (or is
// indistinguishable from) the worktree's cli/ tree, and a human-readable
// diagnostic when cli/ has drifted since the build.
//
// Silent skips (return ""):
//   - buildCommit empty or "unknown" — built without ldflags (local
//     `go run` paths and CI builds without -X cmd.commit). The runtime
//     can't make the comparison; surfacing a warning here would be
//     noise during day-to-day dev.
//   - projDir doesn't have a `.git/` directory at its top — tarball
//     install or sparse layout. Without the project's own git repo
//     we can't make the comparison (and git would walk upward to a
//     parent repo, producing false positives).
//   - `git diff` errors with anything other than exit-1 — the build
//     commit isn't in the local repo (sparse fetch, fresh clone),
//     git itself isn't installed. None of these are the
//     stale-binary case; staying silent avoids false positives.
//
// The exit-1 from `git diff --quiet` specifically means "differences
// found" — that's the only positive signal that returns a diagnostic.
func IsStale(projDir, buildCommit string) string {
	if buildCommit == "" || buildCommit == "unknown" {
		return ""
	}
	// Require .git AT projDir (not somewhere up the tree). Otherwise
	// git's upward search finds the wrong repo and produces false
	// positives. Production tarball installs (no .git) silently skip.
	if _, err := os.Stat(filepath.Join(projDir, ".git")); err != nil {
		return ""
	}

	cmd := exec.Command("git", "diff", "--quiet", buildCommit, "--", "cli/")
	cmd.Dir = projDir
	err := cmd.Run()
	if err == nil {
		return ""
	}
	exitErr, ok := err.(*exec.ExitError)
	if !ok || exitErr.ExitCode() != 1 {
		// Anything other than "differences found" → silent skip.
		return ""
	}

	short := buildCommit
	if len(short) > 8 {
		short = short[:8]
	}
	return fmt.Sprintf(
		"./sb is stale: built from %s, but cli/ has changed since.\n"+
			"  Rebuild: (cd cli && go build -o ../sb .)\n"+
			"  Or run via dev.sh (auto-rebuilds): ./dev.sh <command>",
		short)
}
