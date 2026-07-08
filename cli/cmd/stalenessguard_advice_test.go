package cmd

import (
	"os"
	"strings"
	"testing"
)

// TestStalenessGuardAdviceIsToolchainFree pins STATBUS-085: stalenessGuard's
// refuse-with-guidance branches must propose an action that WORKS on the box the
// error appears on — a toolchain-less production/Albania box. The two branches
// that used to advise `./dev.sh cross-build-sb` (impossible there) must not
// regress to it as the primary remedy.
//   - Ambiguous identity (commitSHA==""): re-fetch a release binary via the rescue
//     bootstrap (it cannot self-heal — no identity to procure against).
//   - Stale-but-identified non-self-heal: `./sb install` (toolchain-free procure),
//     via the freshness.IsStale message.
// A Go-toolchain fallback may appear, but only clearly marked for dev boxes.
func TestStalenessGuardAdviceIsToolchainFree(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/root.go"))
	if err != nil {
		t.Fatalf("read root.go: %v", err)
	}
	body := string(src)

	// Positive: Branch A now points at the no-toolchain rescue bootstrap.
	if !strings.Contains(body, "https://statbus.org/install.sh") {
		t.Error("Branch A (ambiguous identity) must advise the no-toolchain rescue bootstrap (curl … statbus.org/install.sh | bash)")
	}

	// Negative: the old toolchain-PRIMARY advice must not reappear.
	for _, banned := range []string{
		"Rebuild from a clean tree: ./dev.sh cross-build-sb", // old Branch A primary
		"After rebuild, re-run",                              // old toolchain-implying follow-up (both branches)
	} {
		if strings.Contains(body, banned) {
			t.Errorf("STATBUS-085 regression: stale toolchain-primary advice %q must not reappear in stalenessGuard", banned)
		}
	}

	// Any cross-build-sb mention in the guard's advice must be dev-qualified
	// (a secondary line for toolchain boxes), never a bare primary instruction.
	for _, ln := range strings.Split(body, "\n") {
		if strings.Contains(ln, "cross-build-sb") && !strings.Contains(ln, "//") {
			if !strings.Contains(ln, "dev box") && !strings.Contains(ln, "toolchain") {
				t.Errorf("cross-build-sb advice must be marked dev-only (a `dev box`/`toolchain` secondary), got: %s", strings.TrimSpace(ln))
			}
		}
	}
}
