package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// STATBUS-252, SHADOW HALF — deliberately the safe half.
//
// The promotion gate decides on WHOLE-SUITE completeness: a green run at the
// candidate whose job list covers every required scenario. STATBUS-249 built a
// per-SCENARIO answer over the same evidence, and the chain's decision points
// already use it. Before the gate is allowed to switch onto it, we want the two
// answers computed side by side across real candidates so the switch is made
// from evidence rather than from confidence.
//
// SO THIS COMPUTES, PRINTS, AND RETURNS NOTHING THE GATE CAN ACT ON.
// runShadowCoverage has no return value — not "returns a value the callers
// happen to ignore", but no value at all. A shadow that could be consulted
// would, sooner or later, be consulted; making it structurally impossible is
// cheaper than remembering not to. A test pins that too, because a future edit
// could add a return type without noticing why there wasn't one.
//
// WHAT THE OUTPUT IS FOR: the disagreements. Agreement is unremarkable and
// prints in one line. A DIFFERENCE is the whole product of this unit — it says
// either that the per-scenario path would refuse something the gate allows (the
// gate is too lenient, and the switch tightens it), or that it would allow
// something the gate refuses (the gate is too strict, and the switch saves a
// fleet). Both are decision-grade; neither is actionable until the switch is
// ruled.

// shadowCoverageLogEntry is one line of tmp/shadow-coverage-log.jsonl —
// STATBUS-252's durable half. The stdout report above is legible for a human
// watching one run; this is the same facts, one JSON object per gate
// invocation, so the switch decision (per-scenario vs whole-suite) can be
// evaluated later against a HISTORY of real candidates rather than whatever
// happened to be on someone's screen when it printed.
//
// ShadowPassed and Agree are pointers so a refused/undecidable-for-all
// invocation encodes as JSON null, distinct from a real "false" verdict —
// the same rule 4 the stdout report follows (undecidable is its own outcome,
// never folded into either verdict).
type shadowCoverageLogEntry struct {
	Timestamp       string `json:"timestamp"`
	RC              string `json:"rc"`
	Gate            string `json:"gate"`
	AuthorityPassed bool   `json:"authority_passed"`
	ShadowPassed    *bool  `json:"shadow_passed"`
	Agree           *bool  `json:"agree"`
	DomainSize      int    `json:"domain_size"`
	Covered         int    `json:"covered"`
	NotCovered      int    `json:"not_covered"`
	Undecidable     int    `json:"undecidable"`
	RefusalReason   string `json:"refusal_reason,omitempty"`
}

// shadowCoverageLogPath is tmp/shadow-coverage-log.jsonl, gitignored working
// state like every other tmp/ artifact in this codebase (fast-test-passed-sha,
// upgrade-progress.log, ...).
func shadowCoverageLogPath(projDir string) string {
	return filepath.Join(projDir, "tmp", "shadow-coverage-log.jsonl")
}

// appendShadowCoverageLog persists one line per gate invocation. Best-effort,
// deliberately: a write failure here must never reach the gate's own
// pass/fail — this is advisory persistence of an advisory computation, one
// layer removed from anything the gate can act on (see the file header,
// "PRINTS, AND RETURNS NOTHING THE GATE CAN ACT ON"). A failure still prints,
// so a broken log path is visible rather than silently dropping history.
func appendShadowCoverageLog(projDir string, entry shadowCoverageLogEntry) {
	path := shadowCoverageLogPath(projDir)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		fmt.Printf("    (shadow: could not create %s: %v — log line dropped)\n", filepath.Dir(path), err)
		return
	}
	line, err := json.Marshal(entry)
	if err != nil {
		fmt.Printf("    (shadow: could not encode log entry: %v — log line dropped)\n", err)
		return
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		fmt.Printf("    (shadow: could not open %s: %v — log line dropped)\n", path, err)
		return
	}
	defer func() {
		if cerr := f.Close(); cerr != nil {
			fmt.Printf("    (shadow: could not close %s: %v — log line may not be flushed)\n", path, cerr)
		}
	}()
	if _, err := f.Write(append(line, '\n')); err != nil {
		fmt.Printf("    (shadow: could not write to %s: %v — log line dropped)\n", path, err)
	}
}

// shadowScenarioVerdict is one scenario's per-scenario answer, kept separate
// from the gate's own vocabulary so the two can never be confused in a log.
type shadowScenarioVerdict struct {
	Scenario string
	Kind     release.CoverageKind
	Summary  string
	// Err is set when the answer could not be determined. UNDECIDABLE IS ITS
	// OWN OUTCOME (rule 4): mapping it onto covered would manufacture proof, and
	// mapping it onto not-covered would manufacture a disagreement that is
	// really an outage. Neither is honest, so it prints as itself.
	Err error
}

// runShadowCoverage computes the per-scenario answer for every scenario in the
// TARGET COMMIT's domain and prints it beside the gate's authority verdict.
//
// It returns nothing, by design — see the file header.
//
// requiredScenarios MUST be derived from the candidate commit's own tree
// (upgradeArcNamesAtCommit / installRecoveryScenarioNamesAtCommit at rcCommit),
// never from the set of scenarios that happen to have evidence. Deriving the
// domain from the evidence would make the shadow trivially agree with itself:
// every scenario it knew about would be covered, and a scenario deleted from
// the tree — or never run at all — would simply not be asked about. That is the
// zero-scope shape this whole campaign exists to refuse, and it is the one way
// a shadow could be worse than useless: quietly reporting agreement it never
// tested.
func runShadowCoverage(projDir, workflow, rcShort, rcCommit string, requiredScenarios []string, authorityPassed bool) {
	fmt.Printf("    ┌─ SHADOW (STATBUS-252, advisory — does NOT gate) ────────────────\n")

	if len(requiredScenarios) == 0 {
		// Consistent with the STATBUS-216 rule the authority already applies:
		// "is everything covered?" asked of an empty domain is trivially yes.
		fmt.Printf("    │ REFUSING TO REPORT: the scenario domain at %s is EMPTY.\n", rcShort)
		fmt.Printf("    │ A shadow over zero scenarios would agree with anything. The\n")
		fmt.Printf("    │ domain derivation is broken, not the coverage.\n")
		fmt.Printf("    └────────────────────────────────────────────────────────────────\n")
		appendShadowCoverageLog(projDir, shadowCoverageLogEntry{
			Timestamp:       time.Now().UTC().Format(time.RFC3339),
			RC:              rcShort,
			Gate:            workflow,
			AuthorityPassed: authorityPassed,
			RefusalReason:   "empty_domain",
		})
		return
	}

	// A cause shared by every scenario is reported ONCE. Printing it per
	// scenario would put 31 identical lines in front of a reader for a single
	// fact, and volume is how a real finding gets skimmed past.
	if _, sErr := loadUpgradeSensitivePaths(projDir); sErr != nil {
		fmt.Printf("    │ UNDECIDABLE for all %d scenario(s), one shared cause:\n", len(requiredScenarios))
		fmt.Printf("    │   %v\n", sErr)
		fmt.Printf("    │ No comparison is possible, so none is claimed — this is not agreement.\n")
		fmt.Printf("    └────────────────────────────────────────────────────────────────\n")
		appendShadowCoverageLog(projDir, shadowCoverageLogEntry{
			Timestamp:       time.Now().UTC().Format(time.RFC3339),
			RC:              rcShort,
			Gate:            workflow,
			AuthorityPassed: authorityPassed,
			DomainSize:      len(requiredScenarios),
			Undecidable:     len(requiredScenarios),
			RefusalReason:   fmt.Sprintf("sensitive_paths_load_error: %v", sErr),
		})
		return
	}

	verdicts := shadowVerdicts(projDir, workflow, rcCommit, requiredScenarios)

	var covered, notCovered, undecidable []string
	for _, v := range verdicts {
		switch {
		case v.Err != nil:
			undecidable = append(undecidable, fmt.Sprintf("%s (%v)", v.Scenario, v.Err))
		case v.Kind == release.CoverageProvenHere || v.Kind == release.CoverageCoveredBy:
			covered = append(covered, v.Summary)
		default:
			notCovered = append(notCovered, v.Scenario)
		}
	}

	// The shadow's own verdict: it would allow only if EVERY scenario in the
	// domain is covered and none was undecidable. An undecidable scenario is
	// not a pass — the same direction the chain's decision points take.
	shadowPassed := len(notCovered) == 0 && len(undecidable) == 0
	agree := shadowPassed == authorityPassed
	appendShadowCoverageLog(projDir, shadowCoverageLogEntry{
		Timestamp:       time.Now().UTC().Format(time.RFC3339),
		RC:              rcShort,
		Gate:            workflow,
		AuthorityPassed: authorityPassed,
		ShadowPassed:    &shadowPassed,
		Agree:           &agree,
		DomainSize:      len(requiredScenarios),
		Covered:         len(covered),
		NotCovered:      len(notCovered),
		Undecidable:     len(undecidable),
	})

	fmt.Printf("    │ domain: %d scenario(s) from the tree at %s\n", len(requiredScenarios), rcShort)
	fmt.Printf("    │ covered: %d   not covered: %d   undecidable: %d\n",
		len(covered), len(notCovered), len(undecidable))

	// Detail only where it is decision-grade. A long list of "covered" tells
	// nobody anything; the exceptions are the product.
	for _, s := range notCovered {
		fmt.Printf("    │   NOT COVERED: %s\n", s)
	}
	for _, s := range undecidable {
		fmt.Printf("    │   UNDECIDABLE: %s\n", s)
	}

	fmt.Printf("    │\n")
	switch {
	case shadowPassed == authorityPassed:
		fmt.Printf("    │ AGREES with the authority (%s). Nothing to decide.\n", passWord(authorityPassed))
	case authorityPassed && !shadowPassed:
		// The gate is more lenient than the per-scenario path.
		fmt.Printf("    │ ⚠ DISAGREEMENT — the shadow would have REFUSED what the authority ALLOWED.\n")
		fmt.Printf("    │   The whole-suite check found a complete green run; the per-scenario\n")
		fmt.Printf("    │   path found %d scenario(s) without evidence at this code-state.\n", len(notCovered)+len(undecidable))
		fmt.Printf("    │   READ THIS BEFORE THE SWITCH: if the per-scenario path is right, the\n")
		fmt.Printf("    │   gate is currently accepting a candidate on proof that does not cover it.\n")
	default:
		// The gate is stricter than the per-scenario path.
		fmt.Printf("    │ ⚠ DISAGREEMENT — the shadow would have ALLOWED what the authority REFUSED.\n")
		fmt.Printf("    │   Every scenario in the domain has evidence at this code-state, but the\n")
		fmt.Printf("    │   whole-suite check refused (no single complete run, or none at this commit).\n")
		fmt.Printf("    │   READ THIS BEFORE THE SWITCH: if the per-scenario path is right, the gate\n")
		fmt.Printf("    │   is currently re-renting fleets to re-prove work already proven.\n")
	}
	fmt.Printf("    │ The authority above is what decided this run. The shadow decided nothing.\n")
	fmt.Printf("    └────────────────────────────────────────────────────────────────\n")
}

// shadowVerdicts asks the SHARED library — the same DecideCoverage the chain's
// decision points call — one scenario at a time. Same algorithm, same evidence,
// same wording; only the authority differs.
func shadowVerdicts(projDir, workflow, rcCommit string, requiredScenarios []string) []shadowScenarioVerdict {
	sensitivePaths, sErr := loadUpgradeSensitivePaths(projDir)

	out := make([]shadowScenarioVerdict, 0, len(requiredScenarios))
	for _, scenario := range requiredScenarios {
		if sErr != nil {
			out = append(out, shadowScenarioVerdict{Scenario: scenario, Err: fmt.Errorf("sensitive-path list: %w", sErr)})
			continue
		}
		v, err := release.DecideCoverage(scenario, rcCommit, release.CoverageDeps{
			PriorCandidatesNewestFirst: func() ([]string, error) { return priorCandidateTags(projDir, rcCommit) },
			TagCommit:                  func(tag string) (string, error) { return tagTargetCommit(projDir, tag) },
			Evidence:                   release.ScenarioEvidence(projDir, workflow, scenario),
			DiffTouches: func(from, to string) (bool, []string, error) {
				return diffTouchesSensitivePath(projDir, from, to, sensitivePaths)
			},
		})
		if err != nil {
			out = append(out, shadowScenarioVerdict{Scenario: scenario, Err: err})
			continue
		}
		out = append(out, shadowScenarioVerdict{Scenario: scenario, Kind: v.Kind, Summary: v.Summary()})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Scenario < out[j].Scenario })
	return out
}

func passWord(b bool) string {
	if b {
		return "allow"
	}
	return "refuse"
}

// shadowLabel is the authority-side banner, printed by each gate immediately
// before its shadow block so a reader never has to work out which verdict was
// binding.
func shadowLabel(authorityPassed bool) string {
	return fmt.Sprintf("    AUTHORITY: whole-suite completeness — %s (this is what gated this run)",
		strings.ToUpper(passWord(authorityPassed)))
}

// shadowDomainAt derives the required-scenario domain from the TARGET COMMIT's
// own tree (rule 3). On failure it returns an EMPTY domain rather than a
// partial or substituted one, so runShadowCoverage refuses to report instead of
// reporting agreement it never tested — the same direction the authority takes
// when its own domain derivation breaks.
func shadowDomainAt(projDir, rcCommit string, derive func(string, string) ([]string, error)) []string {
	names, err := derive(projDir, rcCommit)
	if err != nil {
		fmt.Printf("    (shadow: the scenario domain at the candidate could not be derived: %v — the shadow will refuse to report rather than guess)\n", err)
		return nil
	}
	return names
}
