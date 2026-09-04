package cmd

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-325: the shell must no longer write remote.origin.fetch at all.
//
// It wrote it twice, with `git remote set-branches --add origin db-seed`, and a
// comment asserting "--add is idempotent; on hosts already broadened it no-ops".
// That claim is false — --add appends unconditionally, so every rescue run left
// one more identical line and gh reached production with three. The false claim
// is why nobody looked: it asserted the very property whose absence was the bug.
//
// The value is now product-owned derived config, rewritten to canonical by
// upgrade.NormalizeRefspecs from ./sb install. The writers are DELETED rather
// than guarded, because a guarded shell writer would be a second mechanism for a
// rule the Go side already enforces exactly — and two mechanisms for one rule is
// how they drift apart.
func TestShellNoLongerWritesRefspecs(t *testing.T) {
	for _, path := range []string{
		"install.sh",
		"ops/create-new-statbus-installation.sh",
	} {
		src, err := os.ReadFile(thisRepoFile(t, path))
		if err != nil {
			// create-new-statbus-installation.sh may not exist in every checkout
			// shape; a missing file is not a failure of this rule.
			continue
		}
		for i, line := range strings.Split(string(src), "\n") {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" || strings.HasPrefix(trimmed, "#") {
				continue // prose describing the retired call is fine, and wanted
			}
			if strings.Contains(line, "set-branches") {
				t.Errorf("%s:%d writes the fetch refspec from the shell: %q\n  remote.origin.fetch is derived config — ./sb install normalizes it (upgrade.NormalizeRefspecs).",
					path, i+1, trimmed)
			}
		}
	}
}

// STATBUS-248: install must never append a per-slot deploy refspec. Such a
// refspec turns deletion of the retired remote branch into a permanent fetch
// failure on that box. CanonicalRefspecs is the only writer authority.
func TestOperationalEntrypointsNoLongerWriteOrAdvertiseDeployBranches(t *testing.T) {
	for _, path := range []string{
		"cli/cmd/install.go",
		"standalone.sh",
	} {
		src, err := os.ReadFile(thisRepoFile(t, path))
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}

		for i, line := range strings.Split(string(src), "\n") {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" || strings.HasPrefix(trimmed, "//") || strings.HasPrefix(trimmed, "#") {
				continue
			}
			if strings.Contains(line, "ops/cloud/deploy/") ||
				strings.Contains(line, "ops/standalone/deploy/") ||
				strings.Contains(line, "configureDeployFetch") {
				t.Errorf("%s:%d still writes or advertises the retired deploy transport: %q", path, i+1, trimmed)
			}
		}
	}
}

// The retired mechanism must not come back. `git config --unset` REFUSES when
// multiple values match, so surgical removal could never clean the triplicated
// state this ticket exists for — it failed silently on its exact target input.
// Normalization replaces wholesale (--unset-all + write canonical) so the result
// is exact by construction rather than by successful subtraction.
func TestRefspecCleanupIsWholesaleNotSurgical(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/refspec.go"))
	if err != nil {
		t.Fatalf("read refspec.go: %v", err)
	}
	body := string(src)

	if !strings.Contains(body, "--unset-all") {
		t.Error("normalization must use --unset-all; --unset refuses on multiple matching values, which is precisely the tripled state")
	}
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			continue // the comment explains why --unset was wrong; that must stay
		}
		if strings.Contains(line, `"--unset"`) {
			t.Errorf("surgical --unset is back: %q", trimmed)
		}
	}

	// THE DECLARATION. Derivation is separated from a quiet self-heal only by
	// saying so: without it, the first person to hand-tune a refspec discovers
	// the policy by silent revert.
	// Case-insensitive: the declaration is written in caps as a banner, and a
	// case-sensitive check here failed on my own text — the assertion, not the
	// policy, was wrong.
	lower := strings.ToLower(body)
	for _, phrase := range []string{
		"product-owned",
		"hand edits",
		"rewritten canonically", // the "on every install and upgrade" half
	} {
		if !strings.Contains(lower, phrase) {
			t.Errorf("the normalizer must declare its ownership policy (missing %q) — a silently reverted value with no stated owner is indistinguishable from a bug", phrase)
		}
	}
}
