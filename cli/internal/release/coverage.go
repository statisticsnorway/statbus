package release

import "fmt"

// Coverage is the ONE algorithm behind two call sites (STATBUS-249, the King's
// "same by design, not by chance"): the promotion gate's anchor-and-walk-back,
// and the `./sb release covered <scenario> <commit>` subcommand the chain jobs
// run. Before this, the walk lived inline in cmd/release.go's
// checkUpgradeArcHarnessGate with its decision interleaved with operator-facing
// printing, so a second caller could only have re-implemented it — and a
// re-implementation that drifts is how two answers to one question appear.
//
// The decision is therefore pure: it takes its inputs as functions and returns a
// VERDICT the caller renders. It performs no printing and no I/O of its own.
//
// WHAT IT DECIDES: may `scenario` be considered proven at `targetCommit`?
//   - PROVEN HERE  — evidence exists at the target commit itself.
//   - COVERED BY   — evidence exists at an ANCHOR commit, and nothing that
//     could invalidate it changed between the anchor and the target.
//   - NOT COVERED  — neither; the scenario must run.
//
// The anchor is always the NEWEST prior candidate with evidence. That is not a
// preference but a proof (STATBUS-199 D2): the newest anchor's diff range to the
// target is the SMALLEST of any candidate's, so if a sensitive path changed
// since it, that same change lies inside every older candidate's larger range
// too. No older anchor can be ridable, which is why the walk STOPS at the first
// sensitive-path hit instead of re-deriving the same refusal N more times.

// CoverageKind is the THREE-WAY answer. A boolean would collapse "proven here"
// and "covered by something else", and that collapse is the STATBUS-249 defect:
// a verdict that cannot distinguish them cannot name what it inherited, so it
// reports a bare success over work that never ran.
type CoverageKind string

const (
	// CoverageProvenHere — evidence exists at the target commit itself.
	CoverageProvenHere CoverageKind = "proven-here"
	// CoverageCoveredBy — evidence exists at Anchor and nothing sensitive
	// changed since. Any message MUST name the anchor (AC#5).
	CoverageCoveredBy CoverageKind = "covered-by"
	// CoverageNotCovered — no usable evidence; the scenario must run.
	CoverageNotCovered CoverageKind = "not-covered"
)

// CoverageVerdict is what the decision returns and both call sites render.
// It carries the REASON, not only the answer, so neither caller has to
// reconstruct why — reconstruction is where two renderings drift apart.
type CoverageVerdict struct {
	Scenario     string
	TargetCommit string
	Kind         CoverageKind

	// Anchor identifies the evidence being ridden (CoverageCoveredBy only):
	// the tag walked to, its commit, and whatever the evidence source wants
	// to say about it (a run URL, a mark's origin).
	Anchor       string
	AnchorCommit string
	AnchorDetail string

	// BlockedBy names the anchor that HAD evidence but could not be ridden,
	// with the sensitive files that changed since it. Populated when the walk
	// stopped for that reason — the operator needs to know a proof existed and
	// why it does not apply, which is different from finding none at all.
	BlockedBy      string
	ChangedPaths   []string
	CandidatesSeen int

	// EvidenceErrors records candidates that could not be evaluated (resolve
	// failures, API errors). They are NOT silently dropped: a walk that skipped
	// half its candidates because of errors and then reported "no evidence
	// found" would be claiming an examination it did not perform.
	EvidenceErrors []string
}

// Summary is the one-line rendering both call sites use, so the operator reads
// the same sentence from the gate and from the subcommand. The King ruled the
// wording: "test <X> is already covered by <Y>".
func (v CoverageVerdict) Summary() string {
	switch v.Kind {
	case CoverageProvenHere:
		return fmt.Sprintf("test %s ran and passed at %s", v.Scenario, shortSHA(v.TargetCommit))
	case CoverageCoveredBy:
		return fmt.Sprintf("test %s is already covered by %s", v.Scenario, v.coveredBySubject())
	default:
		return fmt.Sprintf("test %s is not covered at %s — it must run", v.Scenario, shortSHA(v.TargetCommit))
	}
}

// coveredBySubject names the anchor the way an operator can act on it: the tag
// when we have one, else the commit. Never an empty string — a "covered by"
// message that names nothing is precisely the bare success this ticket removes.
func (v CoverageVerdict) coveredBySubject() string {
	if v.Anchor != "" {
		return v.Anchor
	}
	if v.AnchorCommit != "" {
		return shortSHA(v.AnchorCommit)
	}
	return "an unnamed source (BUG: covered-by must always name its evidence)"
}

// Covered reports whether the scenario need not run. Both "proven here" and
// "covered by" are covered; the distinction is preserved in Kind for the
// message, never collapsed before it reaches the operator.
func (v CoverageVerdict) Covered() bool {
	return v.Kind == CoverageProvenHere || v.Kind == CoverageCoveredBy
}

func shortSHA(sha string) string {
	if len(sha) > 9 {
		return sha[:9]
	}
	return sha
}

// EvidenceAt answers "does evidence exist for this scenario at this commit?".
// It is a function rather than a fixed implementation because the SAME walk must
// serve two evidence sources: today's workflow-run completeness (the gate's
// existing basis) and STATBUS-249's durable marks. Injecting it is what lets the
// algorithm be shared instead of copied.
//
// detail is free-form provenance for the message (a run URL, a mark's origin).
// An error means "could not determine" — which the walk records rather than
// treating as "no evidence", because those are different facts.
type EvidenceAt func(commit string) (found bool, detail string, err error)

// CoverageDeps are the walk's inputs. All are required; DecideCoverage returns
// an error rather than guessing when one is missing, since a walk with no way to
// list candidates would otherwise report a confident "not covered" having
// examined nothing.
type CoverageDeps struct {
	// PriorCandidatesNewestFirst lists candidate tags STRICTLY OLDER than the
	// target, newest first.
	PriorCandidatesNewestFirst func() ([]string, error)
	// TagCommit resolves a candidate tag to its target commit.
	TagCommit func(tag string) (string, error)
	// Evidence answers the per-commit evidence question for THIS scenario.
	Evidence EvidenceAt
	// DiffTouches reports whether anything invalidating changed between two
	// refs, and which files did.
	DiffTouches func(fromRef, toRef string) (touched bool, matched []string, err error)
	// WalkBound caps how far back the walk looks. Zero means the default.
	WalkBound int
}

// DefaultWalkBound matches the gate's existing bound so the shared path does not
// silently change how far back either caller looks.
const DefaultWalkBound = 20

// DecideCoverage runs the anchor-and-walk-back. Pure: no printing, no direct
// I/O, fully testable without a network.
func DecideCoverage(scenario Scenario, targetCommit string, deps CoverageDeps) (CoverageVerdict, error) {
	v := CoverageVerdict{Scenario: scenario.Name, TargetCommit: targetCommit, Kind: CoverageNotCovered}

	if scenario.Name == "" || scenario.Home == "" || targetCommit == "" {
		return v, fmt.Errorf("coverage decision needs a scenario with its home workflow and a target commit (got scenario=%q home=%q commit=%q)", scenario.Name, scenario.Home, targetCommit)
	}
	if deps.Evidence == nil || deps.PriorCandidatesNewestFirst == nil || deps.TagCommit == nil || deps.DiffTouches == nil {
		// Refusing beats answering: a walk missing an input would report
		// "not covered" having examined nothing, which is the zero-scope
		// shape this whole ticket exists to remove.
		return v, fmt.Errorf("coverage decision is missing required inputs — refusing to answer rather than reporting an examination that did not happen")
	}

	// 1. Evidence at the target itself always wins: nothing to inherit, nothing
	//    to diff, and no anchor to name.
	found, detail, err := deps.Evidence(targetCommit)
	if err != nil {
		return v, fmt.Errorf("could not determine whether %s has evidence at %s: %w", scenario.Name, shortSHA(targetCommit), err)
	}
	if found {
		v.Kind = CoverageProvenHere
		v.AnchorDetail = detail
		return v, nil
	}

	// 2. Otherwise walk back for the NEWEST candidate that has evidence.
	candidates, err := deps.PriorCandidatesNewestFirst()
	if err != nil {
		return v, fmt.Errorf("could not list prior candidates to walk back through: %w", err)
	}
	bound := deps.WalkBound
	if bound <= 0 {
		bound = DefaultWalkBound
	}
	if len(candidates) > bound {
		candidates = candidates[:bound]
	}

	for _, candidate := range candidates {
		v.CandidatesSeen++

		candCommit, cerr := deps.TagCommit(candidate)
		if cerr != nil {
			v.EvidenceErrors = append(v.EvidenceErrors, fmt.Sprintf("%s: could not resolve its commit: %v", candidate, cerr))
			continue
		}
		candFound, candDetail, eerr := deps.Evidence(candCommit)
		if eerr != nil {
			v.EvidenceErrors = append(v.EvidenceErrors, fmt.Sprintf("%s: could not read evidence: %v", candidate, eerr))
			continue
		}
		if !candFound {
			continue
		}

		touched, matched, derr := deps.DiffTouches(candidate, targetCommit)
		if derr != nil {
			v.EvidenceErrors = append(v.EvidenceErrors, fmt.Sprintf("%s: has evidence but the diff to the target failed: %v", candidate, derr))
			continue
		}
		if !touched {
			v.Kind = CoverageCoveredBy
			v.Anchor = candidate
			v.AnchorCommit = candCommit
			v.AnchorDetail = candDetail
			return v, nil
		}

		// STATBUS-199 D2: this is the NEWEST candidate with evidence, so its
		// diff range is the smallest. A sensitive change inside it is inside
		// every older candidate's range too — no older anchor can be ridable.
		// Stop rather than re-derive the same refusal.
		v.BlockedBy = candidate
		v.ChangedPaths = matched
		return v, nil
	}

	return v, nil
}
