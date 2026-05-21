package cmd

import (
	"fmt"
	"strings"
	"testing"
)

// TestSeedBranchPattern_MatchesActualShape pins the regex to the
// 8-char short-SHA shape that publishSeedPinBranch actually writes
// (seedSHALen=8). Pre-fix the regex was hard-coded `{12}` while
// the writer used `{8}`, causing cleanupSeedBranches to skip every
// existing branch. Regression guard.
func TestSeedBranchPattern_MatchesActualShape(t *testing.T) {
	// 8-char SHA is the deployed shape — must match.
	if !seedBranchPattern.MatchString("seed/01b96ce7") {
		t.Errorf("seedBranchPattern must match real branch shape seed/<8-hex>; got no match")
	}
	if !seedBranchPattern.MatchString("seed/aabbccdd") {
		t.Errorf("seedBranchPattern must match valid 8-hex shape; got no match for seed/aabbccdd")
	}

	// 12-char SHA is the OLD broken pattern's input — must NOT match.
	if seedBranchPattern.MatchString("seed/01b96ce700ab") {
		t.Errorf("seedBranchPattern must NOT match the old 12-hex shape (no branches of that length exist on origin)")
	}

	// 7-char (too short) → no match.
	if seedBranchPattern.MatchString("seed/01b96ce") {
		t.Errorf("seedBranchPattern must NOT match 7-hex (one short of seedSHALen)")
	}

	// 9-char (too long) → no match.
	if seedBranchPattern.MatchString("seed/01b96ce7a") {
		t.Errorf("seedBranchPattern must NOT match 9-hex (one over seedSHALen)")
	}

	// Non-hex character → no match (uppercase A is outside [0-9a-f]).
	if seedBranchPattern.MatchString("seed/01B96CE7") {
		t.Errorf("seedBranchPattern must NOT match uppercase hex; SHAs are emitted lowercase")
	}

	// Missing prefix → no match.
	if seedBranchPattern.MatchString("01b96ce7") {
		t.Errorf("seedBranchPattern must NOT match bare SHA without seed/ prefix")
	}

	// Different prefix → no match (ops/ branches must stay clear of the sweep).
	if seedBranchPattern.MatchString("ops/01b96ce7") {
		t.Errorf("seedBranchPattern must NOT match ops/ branches")
	}
}

// TestSeedBranchPattern_KeyedOffConstant guards against the constant
// and the regex falling out of sync again. If a future engineer
// changes seedSHALen, the pattern must follow automatically.
func TestSeedBranchPattern_KeyedOffConstant(t *testing.T) {
	expected := fmt.Sprintf(`^seed/[0-9a-f]{%d}$`, seedSHALen)
	if seedBranchPattern.String() != expected {
		t.Errorf("seedBranchPattern out of sync with seedSHALen.\n  pattern: %q\n  want:    %q\n  (the regex must be computed from seedSHALen so future drift is impossible)",
			seedBranchPattern.String(), expected)
	}

	// Sanity: an 8-character sample built from a real-looking SHA matches.
	sampleSHA := strings.Repeat("a", seedSHALen)
	if !seedBranchPattern.MatchString("seed/" + sampleSHA) {
		t.Errorf("seedBranchPattern doesn't match seed/%s (seedSHALen=%d)", sampleSHA, seedSHALen)
	}
}
