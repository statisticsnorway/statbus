package upgrade

import (
	"fmt"
	"os/exec"
	"strings"
)

// CanonicalRefspecs is what remote.origin.fetch must be on every box, however
// that box was born and however many times install has run.
//
// The db-seed entry is redundant under the wildcard above it — refs/heads/*
// already matches refs/heads/db-seed. It is kept because it is the canonical
// set the product declares, and because an explicit line is what a reader (and
// a grep) finds when asking whether this box fetches the seed branch. A
// duplicate fetch of one ref costs nothing; an ambiguous declaration costs an
// afternoon.
var CanonicalRefspecs = []string{
	"+refs/heads/*:refs/remotes/origin/*",
	"+refs/heads/db-seed:refs/remotes/origin/db-seed",
}

// NormalizeRefspecs rewrites remote.origin.fetch to exactly CanonicalRefspecs.
//
// ─────────────────────────────────────────────────────────────────────────────
// DECLARATION: remote.origin.fetch is PRODUCT-OWNED, DERIVED CONFIGURATION.
// It is rewritten canonically on every install and on every upgrade. Hand edits
// to this value do not survive and are not supported. If a box needs a
// different fetch configuration, that is a change to this list, not to the box.
// ─────────────────────────────────────────────────────────────────────────────
//
// That declaration is what separates DERIVATION from a quiet self-heal. Without
// it stated here, the first person to hand-tune a refspec discovers the policy
// by silent revert — and a value that is silently reverted without a stated
// owner is indistinguishable from a bug.
//
// WHY IT EXISTS (STATBUS-325), both defects reproduced in a scratch origin
// before this was written:
//
//  1. `git clone --depth 1 --branch <TAG>` writes exactly ONE refspec — the tag
//     pin, `+refs/tags/vX:refs/tags/vX` — and no wildcard at all. Every box born
//     from the shallow-clone bootstrap starts unable to fetch branches. gh
//     reached production in exactly this state.
//
//  2. `git remote set-branches --add origin db-seed` APPENDS unconditionally.
//     Three installs produce three identical db-seed lines. gh had three.
//
// WHY WHOLESALE REPLACEMENT RATHER THAN SURGICAL REMOVAL, and why the previous
// mechanism could never have worked: the predecessor removed entries with
// `git config --unset <regex>`, and `--unset` REFUSES when multiple values
// match. Against the tripled state — the very case this ticket exists for — it
// could not clean anything. It failed silently on its exact target input. So
// this is not doctrine replacing working practice; it is a working mechanism
// replacing one that never functioned on the input it was aimed at.
//
// --unset-all followed by the canonical adds makes the result exact BY
// CONSTRUCTION rather than by successful subtraction: whatever the box had —
// narrow tag pin, triplicated seed lines, stale devops/ entries from the R1.1
// rename, hand edits — the outcome is identical. That also makes it idempotent,
// so it needs no guard at a call site that runs on every tick.
//
// Best-effort by design: a failure here is reported by the caller and never
// aborts an install or an upgrade. The downstream fetch will fail with its own
// accurate error if the refspec really is unusable, and the two correlate in the
// log.
func NormalizeRefspecs(projDir string) error {
	// Not a git repo (or no remote yet) → nothing to normalize. Distinguished
	// from a real failure so callers do not report a problem on a fresh box.
	probe := exec.Command("git", "rev-parse", "--git-dir")
	probe.Dir = projDir
	if err := probe.Run(); err != nil {
		return nil
	}

	// Exit status 5 is git's "the key does not exist" for --unset-all, which is
	// the ordinary state on a box that has no fetch refspec at all. Not an error.
	unset := exec.Command("git", "config", "--unset-all", "remote.origin.fetch")
	unset.Dir = projDir
	if err := unset.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); !ok || ee.ExitCode() != 5 {
			return fmt.Errorf("clear remote.origin.fetch: %w", err)
		}
	}

	for _, spec := range CanonicalRefspecs {
		add := exec.Command("git", "config", "--add", "remote.origin.fetch", spec)
		add.Dir = projDir
		if out, err := add.CombinedOutput(); err != nil {
			return fmt.Errorf("set refspec %q: %w (%s)", spec, err, strings.TrimSpace(string(out)))
		}
	}
	return nil
}
