package upgrade

// STATBUS-196 unit 5 — the DIAGRAM DRIFT GATE.
//
// The upgrade diagrams double as the operator-facing coverage map
// (doc/upgrade-timeline.md § Diagrams, and the two-way join in
// test/install-recovery/README.md § Coverage join table). This gate fails
// loudly when a new upgrade-row state, phase-dispatch arm, recovery cause, or
// park writer lands in cli/internal/upgrade without its diagram line — the
// drift class that let the prose and the coverage notes fall a full era behind
// the code (STATBUS-196 units 1–3 paid that debt down; this gate keeps it down).
//
// Shape: ONE fast declarative test, enforced by the CI Go gates every push
// already runs — never a slow blocking local hook. The gate watches the
// visible artifacts on both sides: this package's sources vs the diagram
// sources + the recovery model.
//
// TestDiagramDrift_GateFires is the standing probe (AC#5): it pushes a
// synthetic element through the same checker and asserts the gate reports it
// missing, so the gate's own ability to fire is itself pinned on every run.

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

const (
	lifecycleDiagram = "doc/diagrams/upgrade-lifecycle.plantuml"
	timelineDiagram  = "doc/diagrams/upgrade-timeline.plantuml"
	installDiagram   = "doc/diagrams/install-recovery.plantuml"
	recoveryModelDoc = "doc/upgrade-recovery-model.md"
)

func mustReadRepoFile(t *testing.T, relPath string) []byte {
	t.Helper()
	b, err := os.ReadFile(thisRepoFile(t, relPath))
	if err != nil {
		t.Fatalf("drift gate cannot read %s: %v", relPath, err)
	}
	return b
}

// packageGoSources returns the non-test .go sources of this package,
// keyed by file name.
func packageGoSources(t *testing.T) map[string][]byte {
	t.Helper()
	dir := thisRepoFile(t, "cli/internal/upgrade")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("drift gate cannot list %s: %v", dir, err)
	}
	sources := map[string][]byte{}
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatalf("drift gate cannot read %s: %v", name, err)
		}
		sources[name] = b
	}
	if len(sources) == 0 {
		t.Fatal("drift gate found no package sources — path resolution broke")
	}
	return sources
}

// missingFromDocs returns the tokens that appear in NONE of the given docs.
// This is the gate's core; TestDiagramDrift_GateFires pins that it fires.
func missingFromDocs(tokens []string, docs ...[]byte) []string {
	var missing []string
	for _, tok := range tokens {
		found := false
		for _, d := range docs {
			if strings.Contains(string(d), tok) {
				found = true
				break
			}
		}
		if !found {
			missing = append(missing, tok)
		}
	}
	return missing
}

// TestDiagramDrift_StateLiterals: every public.upgrade state name this package
// touches in SQL must have its line in the lifecycle diagram. A new (or
// renamed) state that the code reads or writes without a diagram line is
// exactly the drift this gate exists to stop.
func TestDiagramDrift_StateLiterals(t *testing.T) {
	stateRe := regexp.MustCompile(`state\s*=\s*'([a-z_]+)'`)
	set := map[string]struct{}{}
	for _, src := range packageGoSources(t) {
		for _, m := range stateRe.FindAllStringSubmatch(string(src), -1) {
			set[m[1]] = struct{}{}
		}
	}
	if len(set) == 0 {
		t.Fatal("drift gate found no state literals in cli/internal/upgrade — the scanner regex broke")
	}
	var states []string
	for s := range set {
		states = append(states, s)
	}
	sort.Strings(states)
	diagram := mustReadRepoFile(t, lifecycleDiagram)
	if missing := missingFromDocs(states, diagram); len(missing) > 0 {
		t.Fatalf("DIAGRAM DRIFT — upgrade-row state(s) %v are used by cli/internal/upgrade "+
			"but have no line in %s.\nRemedy: add the state (its transitions and its TESTCOV "+
			"coverage entry) to the diagram, update the join table in "+
			"test/install-recovery/README.md, and keep doc/upgrade-timeline.md § "+
			"Upgrade-row lifecycle in step. See STATBUS-196.", missing, lifecycleDiagram)
	}
}

// TestDiagramDrift_PhaseDispatchArms: every canonical flag phase (the
// recoverFromFlag dispatch arms) must be named in the timeline diagram. The
// inventory is the code's own canonicalPhaseBytes table, so a new phase
// constant fails this test until its diagram band/branch exists.
func TestDiagramDrift_PhaseDispatchArms(t *testing.T) {
	var names []string
	for stored := range canonicalPhaseBytes {
		if stored == PhaseOldSbUpgrading {
			// The default phase stores "" (absence is the value); the diagrams
			// name it by its display slug.
			names = append(names, "old-sb-upgrading")
			continue
		}
		names = append(names, stored)
	}
	sort.Strings(names)
	diagram := mustReadRepoFile(t, timelineDiagram)
	if missing := missingFromDocs(names, diagram); len(missing) > 0 {
		t.Fatalf("DIAGRAM DRIFT — flag phase(s) %v exist in canonicalPhaseBytes but are not "+
			"named in %s.\nRemedy: add the phase's band/dispatch branch to the sequence "+
			"diagram (and its recovery arm to the recoverFromFlag alt block), then update "+
			"doc/upgrade-timeline.md § Binary-swap restart + resume. See STATBUS-196.",
			missing, timelineDiagram)
	}
}

// TestDiagramDrift_RecoveryCauses: the UnknownCause classifier is the curated
// known-intermittent vocabulary at the position-read surface. Two invariants:
// (1) String() stays exhaustive over the declared constants, so every cause
// has a stable doc token; (2) every cause token (except the "none" sentinel)
// is named in the lifecycle diagram's §3 error classifier or the recovery
// model. A new cause without its doc line fails here.
func TestDiagramDrift_RecoveryCauses(t *testing.T) {
	src := string(mustReadRepoFile(t, "cli/internal/upgrade/recovery_backoff.go"))

	constRe := regexp.MustCompile(`(?m)^\tCause[A-Za-z0-9]+`)
	consts := constRe.FindAllString(src, -1)
	if len(consts) == 0 {
		t.Fatal("drift gate found no Cause* constants in recovery_backoff.go — the scanner broke")
	}

	start := strings.Index(src, "func (c UnknownCause) String() string")
	if start < 0 {
		t.Fatal("drift gate cannot find UnknownCause.String() in recovery_backoff.go")
	}
	end := strings.Index(src[start:], "\n}")
	if end < 0 {
		t.Fatal("drift gate cannot find the end of UnknownCause.String()")
	}
	body := src[start : start+end]
	litRe := regexp.MustCompile(`return "([a-z][a-z-]*)"`)
	var tokens []string
	for _, m := range litRe.FindAllStringSubmatch(body, -1) {
		tokens = append(tokens, m[1])
	}

	if len(tokens) != len(consts) {
		t.Fatalf("DIAGRAM DRIFT — %d Cause* constants declared but String() names %d "+
			"(%v).\nRemedy: give the new cause its String() case (the doc token), then its "+
			"line in the §3 error classifier (%s and/or %s). See STATBUS-196.",
			len(consts), len(tokens), tokens, lifecycleDiagram, recoveryModelDoc)
	}

	var docTokens []string
	for _, tok := range tokens {
		if tok == "none" { // CauseNone: not a dispatch arm, no doc line owed
			continue
		}
		docTokens = append(docTokens, tok)
	}
	lifecycle := mustReadRepoFile(t, lifecycleDiagram)
	model := mustReadRepoFile(t, recoveryModelDoc)
	if missing := missingFromDocs(docTokens, lifecycle, model); len(missing) > 0 {
		t.Fatalf("DIAGRAM DRIFT — recovery cause(s) %v have no line in %s or %s.\nRemedy: "+
			"name the cause in the §3 error classifier (intermittent → backoff-retry, or "+
			"unknown → human stop) in both places. See STATBUS-196.",
			missing, lifecycleDiagram, recoveryModelDoc)
	}
}

// TestDiagramDrift_SingleParkWriter: the park marker has exactly ONE SQL write
// site — parkUpgrade's atomic guarded UPDATE (STATBUS-154/159/193: park
// columns + error narrative in one teardown-immune write, `recovery_parked_at
// IS NULL` guard). A second write site would bypass the guard, the siren-once
// contract, and the diagram's park story all at once — so its appearance fails
// here until both the invariant and the diagram are deliberately reworked.
func TestDiagramDrift_SingleParkWriter(t *testing.T) {
	parkWriteRe := regexp.MustCompile(`recovery_parked_at\s*=\s*now\(\)`)
	writers := map[string]int{}
	total := 0
	for name, src := range packageGoSources(t) {
		n := len(parkWriteRe.FindAllIndex(src, -1))
		if n > 0 {
			writers[name] = n
			total += n
		}
	}
	if total != 1 || writers["service.go"] != 1 {
		t.Fatalf("DIAGRAM DRIFT — expected exactly ONE park write site "+
			"(parkUpgrade in service.go, the atomic guarded UPDATE), found %v.\nRemedy: "+
			"route every park through parkUpgrade; if a second writer is genuinely needed, "+
			"that is a design change — update the PARKED story in %s, "+
			"doc/upgrade-recovery-model.md §4/§5, and this pin together. See STATBUS-196/193.",
			writers, lifecycleDiagram)
	}
	src := string(packageGoSources(t)["service.go"])
	writeIdx := parkWriteRe.FindStringIndex(src)[0]
	funcIdx := strings.Index(src, "func (d *Service) parkUpgrade(")
	nextFunc := strings.Index(src[funcIdx+1:], "\nfunc ")
	if funcIdx < 0 || writeIdx < funcIdx || (nextFunc >= 0 && writeIdx > funcIdx+1+nextFunc) {
		t.Fatalf("DIAGRAM DRIFT — the park write moved out of parkUpgrade (write at byte %d, "+
			"parkUpgrade at byte %d).\nRemedy: keep the single atomic write inside parkUpgrade, "+
			"or rework the invariant deliberately (see the pin above).", writeIdx, funcIdx)
	}
	if missing := missingFromDocs([]string{"PARKED"}, mustReadRepoFile(t, lifecycleDiagram)); len(missing) > 0 {
		t.Fatalf("DIAGRAM DRIFT — %s no longer names the PARKED self-loop the park writer "+
			"implements. Restore the park story to the diagram.", lifecycleDiagram)
	}
}

// TestDiagramDrift_GateFires is the AC#5 probe: a synthetic element that no
// diagram names MUST be reported missing by the same checker every real check
// uses. If this fails, the gate itself has gone soft — fix the gate before
// trusting any green above.
func TestDiagramDrift_GateFires(t *testing.T) {
	docs := [][]byte{
		mustReadRepoFile(t, lifecycleDiagram),
		mustReadRepoFile(t, timelineDiagram),
		mustReadRepoFile(t, installDiagram),
		mustReadRepoFile(t, recoveryModelDoc),
	}
	probe := "zz-drift-gate-probe-element"
	missing := missingFromDocs([]string{probe, "in_progress"}, docs...)
	if len(missing) != 1 || missing[0] != probe {
		t.Fatalf("THE DRIFT GATE DOES NOT FIRE — a synthetic element unknown to every diagram "+
			"was not reported missing (got %v). The gate is broken; no drift check above can "+
			"be trusted until this is fixed.", missing)
	}
}
