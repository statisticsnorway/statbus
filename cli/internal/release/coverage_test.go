package release

import (
	"errors"
	"strings"
	"testing"
)

// STATBUS-249: the coverage decision is ONE algorithm serving the promotion gate
// and the `./sb release covered` subcommand. These pin the behaviour that makes
// the specimen (rc.07 inheriting from an unproven rc.06 and reporting a bare
// "success") inexpressible:
//
//  1. inheritance requires EVIDENCE, never a tag's existence;
//  2. a verdict that inherited NAMES what it inherited from;
//  3. "proven here" and "covered by" stay distinct all the way to the message.

// fakeDeps builds a walk whose evidence is a set of commits, so the tests state
// their world explicitly rather than reaching for a network.
func fakeDeps(evidenceAt map[string]string, tagCommits map[string]string, order []string, sensitive map[string]bool) CoverageDeps {
	return CoverageDeps{
		PriorCandidatesNewestFirst: func() ([]string, error) { return order, nil },
		TagCommit: func(tag string) (string, error) {
			c, ok := tagCommits[tag]
			if !ok {
				return "", errors.New("no such tag")
			}
			return c, nil
		},
		Evidence: func(commit string) (bool, string, error) {
			d, ok := evidenceAt[commit]
			return ok, d, nil
		},
		DiffTouches: func(from, to string) (bool, []string, error) {
			if sensitive[from] {
				return true, []string{"cli/internal/upgrade/service.go"}, nil
			}
			return false, nil, nil
		},
	}
}

// TestCoverage_TheRC07Specimen_STATBUS249 is AC#7 replayed as a unit: rc.07 is
// cut, its predecessor rc.06 was CANCELLED so it has no evidence, and nothing
// sensitive changed. The old mechanism compared tag NAMES, found no sensitive
// change against the previous tag, skipped, and reported success.
//
// The new mechanism cannot express that: there is no evidence at rc.06 to find,
// so rc.06 is not an anchor. The walk continues to rc.05, which DOES have
// evidence — and the verdict says so BY NAME instead of reporting a bare pass.
func TestCoverage_TheRC07Specimen_STATBUS249(t *testing.T) {
	deps := fakeDeps(
		// rc.06 deliberately absent: its fleets were cancelled mid-chain.
		map[string]string{"c05": "arc fleet green at rc.05"},
		map[string]string{"v-rc.06": "c06", "v-rc.05": "c05"},
		[]string{"v-rc.06", "v-rc.05"},
		nil,
	)

	v, err := DecideCoverage(arc("rollback-pair-terminal"), "c07", deps)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if v.Kind != CoverageCoveredBy {
		t.Fatalf("expected covered-by (rc.05 has evidence and nothing sensitive changed), got %q", v.Kind)
	}
	if v.Anchor == "v-rc.06" {
		t.Fatal("THE SPECIMEN: inherited from rc.06, which was cancelled and never proved anything — evidence, not tag order, must select the anchor")
	}
	if v.Anchor != "v-rc.05" {
		t.Errorf("expected the anchor to be the newest candidate WITH EVIDENCE (v-rc.05), got %q", v.Anchor)
	}
	// AC#5: the verdict must name its source, in the King's ruled wording.
	got := v.Summary()
	if !strings.Contains(got, "is already covered by") || !strings.Contains(got, "v-rc.05") {
		t.Errorf("an inherited verdict must say what covered it, in the ruled wording; got %q", got)
	}
}

// TestCoverage_UnprovenPredecessorIsNotAnAnchor_STATBUS249 is AC#3 stated
// directly: with NO evidence anywhere, the answer is "not covered". There is no
// arrangement of tags that produces an inherited pass, because inheritance reads
// evidence and none exists.
func TestCoverage_UnprovenPredecessorIsNotAnAnchor_STATBUS249(t *testing.T) {
	deps := fakeDeps(
		map[string]string{}, // nothing was ever proven
		map[string]string{"v-rc.06": "c06", "v-rc.05": "c05"},
		[]string{"v-rc.06", "v-rc.05"},
		nil,
	)

	v, err := DecideCoverage(arc("rollback-pair-terminal"), "c07", deps)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if v.Covered() {
		t.Fatalf("inheriting from something never proven must be IMPOSSIBLE, not merely reported; got %q covered by %q", v.Kind, v.Anchor)
	}
	if !strings.Contains(v.Summary(), "must run") {
		t.Errorf("an uncovered verdict must say the scenario has to run; got %q", v.Summary())
	}
	if v.CandidatesSeen != 2 {
		t.Errorf("the walk must report what it examined — expected 2 candidates seen, got %d", v.CandidatesSeen)
	}
}

// TestCoverage_ProvenHereIsNotCoveredBy_STATBUS249 keeps the two "yes" answers
// distinct. Collapsing them into a boolean is what let a verdict report success
// over work that never ran.
func TestCoverage_ProvenHereIsNotCoveredBy_STATBUS249(t *testing.T) {
	deps := fakeDeps(
		map[string]string{"c07": "ran in this very chain"},
		map[string]string{"v-rc.06": "c06"},
		[]string{"v-rc.06"},
		nil,
	)

	v, err := DecideCoverage(arc("un-park-to-completion"), "c07", deps)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if v.Kind != CoverageProvenHere {
		t.Fatalf("evidence at the target itself is PROVEN HERE, got %q", v.Kind)
	}
	if v.Anchor != "" {
		t.Errorf("proven-here must name no anchor — there is nothing inherited; got %q", v.Anchor)
	}
	if strings.Contains(v.Summary(), "covered by") {
		t.Errorf("proven-here must NOT claim inheritance; got %q", v.Summary())
	}
}

// TestCoverage_SensitiveChangeBlocksTheNewestAnchor_STATBUS249 pins the
// STATBUS-199 D2 stop: the newest anchor has the smallest diff range, so a
// sensitive change inside it rules out every older anchor too. Walking on would
// re-derive the same refusal; more importantly, riding an OLDER anchor whose
// range CONTAINS the same change would be wrong.
func TestCoverage_SensitiveChangeBlocksTheNewestAnchor_STATBUS249(t *testing.T) {
	deps := fakeDeps(
		map[string]string{"c06": "green at rc.06", "c05": "green at rc.05"},
		map[string]string{"v-rc.06": "c06", "v-rc.05": "c05"},
		[]string{"v-rc.06", "v-rc.05"},
		map[string]bool{"v-rc.06": true, "v-rc.05": true},
	)

	v, err := DecideCoverage(arc("rollback-pair-terminal"), "c07", deps)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if v.Covered() {
		t.Fatal("a sensitive change since the newest anchor must BLOCK the ride — riding an older anchor whose range contains the same change would be worse, not better")
	}
	if v.BlockedBy != "v-rc.06" {
		t.Errorf("the verdict must name the anchor it could not ride (v-rc.06), got %q", v.BlockedBy)
	}
	if len(v.ChangedPaths) == 0 {
		t.Error("the verdict must name WHICH files changed — otherwise the operator cannot tell whether the block is right")
	}
	if v.CandidatesSeen != 1 {
		t.Errorf("the walk must STOP at the newest anchor with evidence (STATBUS-199 D2), got %d candidates seen", v.CandidatesSeen)
	}
}

// TestCoverage_UnevaluableCandidatesAreReported_STATBUS249: a candidate we could
// not evaluate is not a candidate without evidence. Silently treating an API
// error as "no evidence" would let a walk claim it examined a history it could
// not read — the same zero-scope shape in a new costume.
func TestCoverage_UnevaluableCandidatesAreReported_STATBUS249(t *testing.T) {
	deps := CoverageDeps{
		PriorCandidatesNewestFirst: func() ([]string, error) { return []string{"v-rc.06"}, nil },
		TagCommit:                  func(string) (string, error) { return "", errors.New("ls-remote failed") },
		Evidence:                   func(string) (bool, string, error) { return false, "", nil },
		DiffTouches:                func(string, string) (bool, []string, error) { return false, nil, nil },
	}

	v, err := DecideCoverage(arc("rollback-kill"), "c07", deps)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(v.EvidenceErrors) != 1 {
		t.Fatalf("a candidate that could not be evaluated must be RECORDED, not silently dropped; got %d errors", len(v.EvidenceErrors))
	}
	if !strings.Contains(v.EvidenceErrors[0], "ls-remote failed") {
		t.Errorf("the recorded error must carry the underlying cause; got %q", v.EvidenceErrors[0])
	}
}

// TestCoverage_RefusesWithoutItsInputs_STATBUS249: a decision missing an input
// must ERROR, never answer. Returning "not covered" would be a check reporting
// on an examination it never performed — over-running a fleet is cheap, but the
// same silence in the other direction is how the specimen happened.
func TestCoverage_RefusesWithoutItsInputs_STATBUS249(t *testing.T) {
	if _, err := DecideCoverage(arc("x"), "c07", CoverageDeps{}); err == nil {
		t.Error("a coverage decision with no evidence source must refuse, not answer")
	}
	if _, err := DecideCoverage(arc(""), "c07", fakeDeps(nil, nil, nil, nil)); err == nil {
		t.Error("a coverage decision with no scenario must refuse")
	}
}

// TestCoverage_CoveredByAlwaysNamesItsSource_STATBUS249 is AC#5 as a property:
// there is no covered-by verdict whose message names nothing. The fallback text
// is deliberately an accusation rather than a neutral blank, so a bug here reads
// as a bug rather than as a tidy sentence.
func TestCoverage_CoveredByAlwaysNamesItsSource_STATBUS249(t *testing.T) {
	v := CoverageVerdict{Scenario: "s", TargetCommit: "c07", Kind: CoverageCoveredBy}
	if !strings.Contains(v.Summary(), "BUG") {
		t.Errorf("a covered-by verdict with no named source must SAY it is a bug rather than print a plausible-looking sentence; got %q", v.Summary())
	}

	v.AnchorCommit = "abcdef1234567890"
	if got := v.Summary(); !strings.Contains(got, "abcdef123") {
		t.Errorf("with no tag, covered-by must name the anchor COMMIT; got %q", got)
	}
}
