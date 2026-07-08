package freshness

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// TestStaleMessageIsToolchainFree pins STATBUS-085: the committed-drift staleness
// message IsStale returns (printed by root.go's stalenessGuard to the operator,
// including on a toolchain-less production box) must lead with the toolchain-free
// remedy `./sb install`, not a bare `./dev.sh (cross-)build-sb` rebuild. A
// Go-toolchain fallback may follow, marked for dev boxes.
func TestStaleMessageIsToolchainFree(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	src, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), "check.go"))
	if err != nil {
		t.Fatalf("read check.go: %v", err)
	}
	body := string(src)

	// Positive: the toolchain-free refresh is the primary remedy.
	if !strings.Contains(body, "./sb install") {
		t.Error("the staleness message must advise the no-toolchain `./sb install` refresh")
	}
	// Negative: the old rebuild-primary lines must not reappear.
	for _, banned := range []string{
		"for dev iteration)",     // old `./dev.sh build-sb (host-only, fast — for dev iteration)` primary
		"for release artifacts)", // old `./dev.sh cross-build-sb (all platforms — for release artifacts)` primary
	} {
		if strings.Contains(body, banned) {
			t.Errorf("STATBUS-085 regression: stale rebuild-primary advice %q must not reappear in IsStale", banned)
		}
	}
	// Any cross-build advice that remains must be dev-qualified, never primary.
	for _, ln := range strings.Split(body, "\n") {
		if strings.Contains(ln, "cross-build-sb") && !strings.HasPrefix(strings.TrimSpace(ln), "//") {
			if !strings.Contains(ln, "dev box") && !strings.Contains(ln, "toolchain") {
				t.Errorf("cross-build-sb advice must be marked dev-only, got: %s", strings.TrimSpace(ln))
			}
		}
	}
}
