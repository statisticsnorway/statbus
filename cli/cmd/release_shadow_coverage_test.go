package cmd

import (
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-252 SHADOW HALF. The whole value of a shadow is that it is safe to be
// WRONG: it computes a second opinion across real candidates so the switch
// decision is made from evidence. That safety rests on one property — the
// shadow cannot change what the gate accepts or refuses — and a property that
// rests on everyone remembering it is not a property.

// TestShadowCannotFeedTheDecision_STATBUS252 is rule 1, pinned structurally
// rather than by inspection.
//
// The strongest available form: runShadowCoverage RETURNS NOTHING. Not "returns
// something the callers ignore" — there is no value to consult, so no future
// edit can quietly start consulting one without first changing the signature,
// which is exactly what this test watches.
func TestShadowCannotFeedTheDecision_STATBUS252(t *testing.T) {
	fset := token.NewFileSet()
	file := thisRepoFile(t, "cli/cmd/release_shadow_coverage.go")
	f, err := parser.ParseFile(fset, file, nil, 0)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}

	var found bool
	ast.Inspect(f, func(n ast.Node) bool {
		fn, ok := n.(*ast.FuncDecl)
		if !ok || fn.Name.Name != "runShadowCoverage" {
			return true
		}
		found = true
		if fn.Type.Results != nil && len(fn.Type.Results.List) > 0 {
			t.Errorf(`runShadowCoverage must return NOTHING (STATBUS-252 rule 1).

It grew a return value, which is the first half of the only way this becomes
unsafe: a shadow that CAN be consulted eventually IS consulted, and the gate's
decision silently starts depending on an advisory computation that was built to
be allowed to be wrong. If the switch has been ruled, this is not the change to
make — the switch replaces the authority, it does not let the shadow vote.`)
		}
		return false
	})
	if !found {
		t.Fatal("runShadowCoverage not found — if it was renamed, this pin must follow it; the property it protects has not stopped mattering")
	}
}

// TestGateDecisionsIgnoreTheShadow_STATBUS252 is the same rule from the caller's
// side: no gate may branch on anything the shadow produced. Reading the call
// sites catches the case the signature check cannot — a caller assigning the
// result of shadowVerdicts and deciding on it directly.
func TestGateDecisionsIgnoreTheShadow_STATBUS252(t *testing.T) {
	b, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release.go"))
	if err != nil {
		t.Fatal(err)
	}
	for i, line := range strings.Split(string(b), "\n") {
		trimmed := strings.TrimSpace(line)
		if !strings.Contains(trimmed, "runShadowCoverage(") && !strings.Contains(trimmed, "shadowVerdicts(") {
			continue
		}
		// A bare statement call is the only legal shape. An assignment, a
		// condition, or a return means the decision can see it.
		if strings.Contains(trimmed, ":=") || strings.Contains(trimmed, " = ") ||
			strings.HasPrefix(trimmed, "if ") || strings.HasPrefix(trimmed, "return ") {
			t.Errorf("release.go:%d — the gate must not consume the shadow's output; it is advisory and is allowed to be wrong:\n  %s", i+1, trimmed)
		}
	}
}

// TestShadowDomainComesFromTheTargetCommit_STATBUS252 is rule 3, and it is the
// zero-scope guard for this unit specifically.
//
// If the domain were derived from the evidence rather than from the candidate's
// tree, the shadow would trivially agree with itself: every scenario it knew
// about would be covered, and a scenario never run — or deleted from the tree —
// would simply never be asked about. A shadow reporting agreement it never
// tested is worse than no shadow, because it would be cited in the switch
// decision as evidence.
func TestShadowDomainComesFromTheTargetCommit_STATBUS252(t *testing.T) {
	b, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release_shadow_coverage.go"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(b)

	if !strings.Contains(src, "func shadowDomainAt(projDir, rcCommit string") {
		t.Error("the domain helper must take the CANDIDATE's commit — deriving the domain from anything else is how a shadow agrees with itself")
	}
	// An empty domain must REFUSE to report, never report agreement.
	if !strings.Contains(src, "REFUSING TO REPORT") {
		t.Error("an empty scenario domain must make the shadow refuse to report: 'is everything covered?' over zero scenarios is trivially yes, and printing agreement there would put a zero-scope pass into the switch evidence (STATBUS-216's rule, one layer over)")
	}
	if !strings.Contains(src, "return nil") {
		t.Error("a failed domain derivation must yield an EMPTY domain (so the shadow refuses), never a partial or substituted one")
	}
}

// TestShadowUndecidableIsItsOwnOutcome_STATBUS252 is rule 4. Mapping
// undecidable onto covered manufactures proof; mapping it onto not-covered
// manufactures a disagreement that is really an API outage — and a fabricated
// disagreement is worse than a missing one here, because disagreements are
// precisely what the switch decision will be read from.
func TestShadowUndecidableIsItsOwnOutcome_STATBUS252(t *testing.T) {
	b, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release_shadow_coverage.go"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(b)
	if !strings.Contains(src, "UNDECIDABLE:") {
		t.Error("undecidable scenarios must print as UNDECIDABLE, distinct from covered and not-covered (rule 4)")
	}
	if !strings.Contains(src, "undecidable: %d") {
		t.Error("the summary line must count undecidable separately — folding it into either verdict is what rule 4 forbids")
	}
	// It must not be silently treated as a pass.
	if !strings.Contains(src, "len(notCovered) == 0 && len(undecidable) == 0") {
		t.Error("the shadow's own verdict must treat an undecidable scenario as NOT a pass — the same direction the chain's decision points take")
	}
}

// TestBothVerdictsAreLabelled_STATBUS252 is rule 2's readability half: a reader
// must never have to work out which verdict was binding.
func TestBothVerdictsAreLabelled_STATBUS252(t *testing.T) {
	b, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release_shadow_coverage.go"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(b)
	for _, want := range []string{
		"AUTHORITY:",         // the binding verdict, named as such
		"this is what gated", // and said plainly
		"does NOT gate",      // the shadow, named as such
		"DISAGREEMENT",       // the product of the unit
		"The shadow decided nothing.",
	} {
		if !strings.Contains(src, want) {
			t.Errorf("the side-by-side output must contain %q so nobody has to infer which verdict was binding", want)
		}
	}

	// Both directions of disagreement must be reported — a shadow that only
	// reported one direction would bias the switch decision it exists to inform.
	if !strings.Contains(src, "REFUSED what the authority ALLOWED") ||
		!strings.Contains(src, "ALLOWED what the authority REFUSED") {
		t.Error("BOTH disagreement directions must be reported: 'gate too lenient' and 'gate too strict' are different findings and the switch needs both")
	}
}

// STATBUS-252 PERSISTENCE HALF (durable log, not just the stdout report).
//
// readShadowLogLines reads back tmp/shadow-coverage-log.jsonl as parsed
// entries — a test helper, not part of the shipped CLI.
func readShadowLogLines(t *testing.T, projDir string) []shadowCoverageLogEntry {
	t.Helper()
	b, err := os.ReadFile(shadowCoverageLogPath(projDir))
	if err != nil {
		t.Fatalf("reading shadow coverage log: %v", err)
	}
	var out []shadowCoverageLogEntry
	for _, line := range strings.Split(strings.TrimRight(string(b), "\n"), "\n") {
		if line == "" {
			continue
		}
		var e shadowCoverageLogEntry
		if err := json.Unmarshal([]byte(line), &e); err != nil {
			t.Fatalf("unmarshal log line %q: %v", line, err)
		}
		out = append(out, e)
	}
	return out
}

// TestShadowCoverageLogPersistsEmptyDomainRefusal_STATBUS252 pins the empty-
// domain exit path (rule 3's own refusal) still gets a durable log line, not
// just a stdout print that vanishes when nobody was watching.
func TestShadowCoverageLogPersistsEmptyDomainRefusal_STATBUS252(t *testing.T) {
	projDir := t.TempDir()
	runShadowCoverage(projDir, "test-gate", "rc.test-empty", "deadbeef", nil, true)

	entries := readShadowLogLines(t, projDir)
	if len(entries) != 1 {
		t.Fatalf("expected exactly 1 log line, got %d", len(entries))
	}
	e := entries[0]
	if e.RC != "rc.test-empty" || e.Gate != "test-gate" {
		t.Errorf("rc/gate not recorded correctly: %+v", e)
	}
	if e.RefusalReason != "empty_domain" {
		t.Errorf("expected refusal_reason=empty_domain, got %q", e.RefusalReason)
	}
	// Rule 4, applied to the log: a refused invocation must not manufacture a
	// verdict or an agreement — both must be absent (JSON null), not false.
	if e.ShadowPassed != nil || e.Agree != nil {
		t.Errorf("a refused invocation must log shadow_passed/agree as null, not a manufactured value: %+v", e)
	}
}

// TestShadowCoverageLogPersistsUndecidableRefusal_STATBUS252 exercises the
// other early-exit (sensitive-paths list unreadable — UNDECIDABLE for every
// scenario in the domain) via a projDir that genuinely lacks the file, so
// this is a real call through runShadowCoverage, not a source-text pin.
func TestShadowCoverageLogPersistsUndecidableRefusal_STATBUS252(t *testing.T) {
	projDir := t.TempDir() // no ops/release/upgrade-sensitive-paths.txt present
	runShadowCoverage(projDir, "test-gate", "rc.test-undecidable", "deadbeef", []string{"scenario-a", "scenario-b"}, false)

	entries := readShadowLogLines(t, projDir)
	if len(entries) != 1 {
		t.Fatalf("expected exactly 1 log line, got %d", len(entries))
	}
	e := entries[0]
	if e.DomainSize != 2 || e.Undecidable != 2 {
		t.Errorf("expected domain_size=2, undecidable=2 (every scenario undecidable), got %+v", e)
	}
	if !strings.Contains(e.RefusalReason, "sensitive_paths_load_error") {
		t.Errorf("expected refusal_reason to name the cause, got %q", e.RefusalReason)
	}
	if e.ShadowPassed != nil || e.Agree != nil {
		t.Errorf("undecidable-for-all must log shadow_passed/agree as null, not a manufactured value: %+v", e)
	}
	if e.AuthorityPassed != false {
		t.Errorf("authority_passed must record what was actually passed in, got %v", e.AuthorityPassed)
	}
}

// TestShadowCoverageLogPathIsUnderProjDirTmp_STATBUS252 pins the location
// (tmp/, gitignored working state, same convention as every other tmp/
// artifact this CLI writes) so a future edit can't quietly relocate it.
func TestShadowCoverageLogPathIsUnderProjDirTmp_STATBUS252(t *testing.T) {
	got := shadowCoverageLogPath("/proj")
	want := filepath.Join("/proj", "tmp", "shadow-coverage-log.jsonl")
	if got != want {
		t.Errorf("shadowCoverageLogPath(%q) = %q, want %q", "/proj", got, want)
	}
}
