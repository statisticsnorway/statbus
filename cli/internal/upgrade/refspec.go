package upgrade

import (
	"fmt"
	"os/exec"
	"strings"
)

// CanonicalRefspecs is what remote.origin.fetch must be on every box, however
// that box was born and however many times install has run.
//
// Only the branch wildcard. Every explicit branch line is a fetch that fails
// with "couldn't find remote ref" the day that branch is deleted, so retired
// transports (the per-slot deploy branches, STATBUS-248; the db-seed branch,
// replaced by the statbus-seed image, STATBUS-553) are removed here first and
// their branches deleted only after every box has normalized.
var CanonicalRefspecs = []string{
	"+refs/heads/*:refs/remotes/origin/*",
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
// CanonicalOriginURL is the one remote every box fetches from. The repo is
// PUBLIC and read-only to the product, so HTTPS needs no credentials — which is
// the whole reason STATBUS-324's deploy-key question dissolved. If the repo ever
// goes private this constant, and the normalization below, are void.
const CanonicalOriginURL = "https://github.com/statisticsnorway/statbus.git"

// NormalizeOriginURL rewrites remote.origin.url to the canonical HTTPS URL
// (STATBUS-324).
//
// WHY: boxes born before the HTTPS convention carry SSH-era origins
// (git@github.com:… or ssh://…). SSH to GitHub needs a key the box may not have,
// and when it fails the operator is debugging key distribution for a repository
// that is public and needs no key at all. New boxes already clone over HTTPS
// (create-new-statbus-installation.sh), so this is a one-line repair for history,
// not a policy change.
//
// Same doctrine as NormalizeRefspecs directly above: remote.origin.url is
// PRODUCT-OWNED, DERIVED CONFIGURATION, set canonically on every install. Hand
// edits do not survive and are not supported. Derivation, not self-heal — it
// runs inside install's step table, the verb that owns derived config, and never
// on a timer.
//
// Idempotent by construction: it writes the canonical value unconditionally when
// the current one differs, and does nothing when it already matches, so it needs
// no guard at its call site.
func NormalizeOriginURL(projDir string) error {
	if !isGitRepo(projDir) {
		return nil
	}

	get := exec.Command("git", "config", "--get", "remote.origin.url")
	get.Dir = projDir
	out, err := get.Output()
	if err != nil {
		// No origin configured at all — nothing to repair, and adding a remote is
		// the clone's job, not this function's.
		return nil
	}
	current := strings.TrimSpace(string(out))
	if current == CanonicalOriginURL {
		return nil
	}

	set := exec.Command("git", "config", "remote.origin.url", CanonicalOriginURL)
	set.Dir = projDir
	if setOut, serr := set.CombinedOutput(); serr != nil {
		return fmt.Errorf("set remote.origin.url to %q (was %q): %w (%s)",
			CanonicalOriginURL, current, serr, strings.TrimSpace(string(setOut)))
	}
	return nil
}

// isGitRepo reports whether projDir is inside a git working tree. Shared so the
// two normalizers agree on what "nothing to do here" means — a fresh box before
// the clone must be a silent no-op in both, never a reported failure.
func isGitRepo(projDir string) bool {
	probe := exec.Command("git", "rev-parse", "--git-dir")
	probe.Dir = projDir
	return probe.Run() == nil
}

func NormalizeRefspecs(projDir string) error {
	// Not a git repo (or no remote yet) → nothing to normalize. Distinguished
	// from a real failure so callers do not report a problem on a fresh box.
	if !isGitRepo(projDir) {
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
