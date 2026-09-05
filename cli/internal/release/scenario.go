package release

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Scenario is a harness scenario that KNOWS which workflow runs it. It is a
// value, not a string, so that "look this scenario up under the wrong
// workflow" is not something a caller can write: the only ways to obtain one
// are ScenariosAt (from the directory listing at a commit, the same listing
// each promotion gate derives its domain from) and ParseScenario (which
// resolves a bare name through that listing and refuses unknown names).
//
// Before this type, `./sb release covered` accepted any string and asked the
// arc harness for every one of them; 13 of 15 install-recovery scenarios read
// "no evidence" against a run that was green on all of them (2026-09-03). The
// two DecideCoverage call sites are supposed to be the same by design
// (STATBUS-249); a value that carries its home makes that so by construction.
type Scenario struct {
	Name string
	Home Workflow
}

// Workflow is one of the harness workflow identities that file scenario
// evidence. Typed so a caller cannot pass an arbitrary workflow file name into
// an evidence lookup.
type Workflow string

const (
	// WorkflowArcs runs every test/install-recovery/arcs/<name>-arc.sh.
	WorkflowArcs Workflow = WorkflowUpgradeArcHarness
	// WorkflowFleet runs every test/install-recovery/scenarios/<name>.sh that
	// is not marked skip-default.
	WorkflowFleet Workflow = WorkflowInstallRecoveryHarness
	// WorkflowSmoke runs the fixed two-scenario happy-path domain.
	WorkflowSmoke Workflow = WorkflowTestSmoke
)

func (w Workflow) String() string { return string(w) }

func (s Scenario) String() string { return s.Name }

// Domain is the scenario set one harness workflow runs at a commit. It is
// derived from git at that commit, never from the working tree, so a gate
// evaluating an RC sees the RC's scenarios and not whatever HEAD has grown.
type Domain struct {
	Workflow  Workflow
	Scenarios []Scenario
}

// SmokeDomain is deliberately fixed. Unlike harness domains it is a release
// contract, not a directory enumeration: both facts must be proven even when a
// selector dispatch runs only the uncovered half.
func SmokeDomain() Domain {
	return Domain{
		Workflow: WorkflowSmoke,
		Scenarios: []Scenario{
			{Name: "0-happy-install", Home: WorkflowSmoke},
			{Name: "0-happy-upgrade", Home: WorkflowSmoke},
		},
	}
}

const (
	arcDir    = "test/install-recovery/arcs/"
	arcSuffix = "-arc.sh"
	fleetDir  = "test/install-recovery/scenarios/"
	// FleetSkipDefaultMarker is the literal a scenario file carries to opt out
	// of the default full suite. It must match test/install-recovery/run.sh's
	// SKIP_DEFAULT_MARKER; cli/cmd's install_recovery_scenario_domain_test pins that.
	FleetSkipDefaultMarker = "HARNESS_SKIP_DEFAULT"
)

// ScenariosAt lists the scenarios a workflow runs at commit, by the same
// directory listing the harness's own discover job uses. An EMPTY domain is an
// error, never a trivially-satisfied gate (STATBUS-216): the directory was
// moved, the path is a typo, or every fleet scenario is marked skip-default.
func ScenariosAt(projDir, commit string, workflow Workflow) (Domain, error) {
	switch workflow {
	case WorkflowArcs:
		return arcsAt(projDir, commit)
	case WorkflowFleet:
		return fleetAt(projDir, commit)
	case WorkflowSmoke:
		return SmokeDomain(), nil
	}
	return Domain{}, fmt.Errorf("%q is not a harness workflow that runs scenarios (want %s, %s, or %s)", workflow, WorkflowArcs, WorkflowFleet, WorkflowSmoke)
}

// ScenarioAt resolves a name inside one explicit workflow domain. Callers must
// use this when a slug exists in more than one home, as both happy-path names do.
func ScenarioAt(projDir, commit, name string, workflow Workflow) (Scenario, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return Scenario{}, fmt.Errorf("a scenario name is required")
	}
	domain, err := ScenariosAt(projDir, commit, workflow)
	if err != nil {
		return Scenario{}, err
	}
	for _, scenario := range domain.Scenarios {
		if scenario.Name == name {
			return scenario, nil
		}
	}
	return Scenario{}, fmt.Errorf("%q is not a scenario in %s at %s", name, workflow, shortSHA(commit))
}

// ParseScenario resolves a bare name at commit to the Scenario that runs it.
// A name found in neither domain is refused: an evidence lookup under a
// guessed workflow can only ever answer "not found", which a caller would
// mistake for "must run".
func ParseScenario(projDir, commit, name string) (Scenario, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return Scenario{}, fmt.Errorf("a scenario name is required")
	}
	var errs []string
	var matches []Scenario
	for _, wf := range []Workflow{WorkflowArcs, WorkflowFleet, WorkflowSmoke} {
		domain, err := ScenariosAt(projDir, commit, wf)
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", wf, err))
			continue
		}
		for _, s := range domain.Scenarios {
			if s.Name == name {
				matches = append(matches, s)
			}
		}
	}
	if len(matches) == 1 {
		return matches[0], nil
	}
	if len(matches) > 1 {
		var homes []string
		for _, match := range matches {
			homes = append(homes, match.Home.String())
		}
		return Scenario{}, fmt.Errorf("%q is ambiguous at %s: it exists in %s; specify the workflow", name, shortSHA(commit), strings.Join(homes, ", "))
	}
	if len(errs) == 2 {
		return Scenario{}, fmt.Errorf("could not list any scenario domain at %s: %s", shortSHA(commit), strings.Join(errs, "; "))
	}
	return Scenario{}, fmt.Errorf("%q is not a scenario at %s: not in %s (arcs), %s (default fleet suite), or %s%s",
		name, shortSHA(commit), arcDir, fleetDir, WorkflowSmoke, notesSuffix(errs))
}

func notesSuffix(errs []string) string {
	if len(errs) == 0 {
		return ""
	}
	return " (note: " + strings.Join(errs, "; ") + ")"
}

func arcsAt(projDir, commit string) (Domain, error) {
	paths, err := gitLsTree(projDir, commit, arcDir)
	if err != nil {
		return Domain{}, err
	}
	d := Domain{Workflow: WorkflowArcs}
	for _, p := range paths {
		base := filepath.Base(p)
		if strings.HasSuffix(base, arcSuffix) {
			d.Scenarios = append(d.Scenarios, Scenario{Name: strings.TrimSuffix(base, arcSuffix), Home: WorkflowArcs})
		}
	}
	if len(d.Scenarios) == 0 {
		return Domain{}, fmt.Errorf("no arc scenarios at %s: `git ls-tree %s -- %s` matched no *%s file. "+
			"The arc domain cannot legitimately be empty; refusing to check completeness against an empty domain (it would pass trivially). "+
			"Fix: keep %s identical to the discover job's path in .github/workflows/upgrade-arc-harness.yaml",
			shortSHA(commit), shortSHA(commit), arcDir, arcSuffix, arcDir)
	}
	return d, nil
}

func fleetAt(projDir, commit string) (Domain, error) {
	paths, err := gitLsTree(projDir, commit, fleetDir)
	if err != nil {
		return Domain{}, err
	}
	d := Domain{Workflow: WorkflowFleet}
	for _, p := range paths {
		if !strings.HasSuffix(p, ".sh") {
			continue
		}
		content, err := gitShow(projDir, commit, p)
		if err != nil {
			return Domain{}, err
		}
		if strings.Contains(content, FleetSkipDefaultMarker) {
			continue
		}
		d.Scenarios = append(d.Scenarios, Scenario{Name: strings.TrimSuffix(filepath.Base(p), ".sh"), Home: WorkflowFleet})
	}
	if len(d.Scenarios) == 0 {
		return Domain{}, fmt.Errorf("no default-suite scenarios at %s: `git ls-tree %s -- %s` matched no .sh file without the %s marker. "+
			"The fleet domain cannot legitimately be empty; refusing to check completeness against an empty domain (it would pass trivially). "+
			"Fix: keep %s pointed at the scenarios directory, or un-mark at least one scenario in test/install-recovery/run.sh's default suite",
			shortSHA(commit), shortSHA(commit), fleetDir, FleetSkipDefaultMarker, fleetDir)
	}
	return d, nil
}

func gitLsTree(projDir, commit, dir string) ([]string, error) {
	out, err := runGit(projDir, "ls-tree", "-r", "--name-only", commit, "--", dir)
	if err != nil {
		return nil, fmt.Errorf("git ls-tree %s -- %s: %w", shortSHA(commit), dir, err)
	}
	var paths []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if p := strings.TrimSpace(line); p != "" {
			paths = append(paths, p)
		}
	}
	return paths, nil
}

func gitShow(projDir, commit, path string) (string, error) {
	out, err := runGit(projDir, "show", commit+":"+path)
	if err != nil {
		return "", fmt.Errorf("git show %s:%s: %w", shortSHA(commit), path, err)
	}
	return out, nil
}

// runGit is the scenario listing's git seam. Local-object reads only; it never
// consults a credential helper or prompts.
func runGit(projDir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = projDir
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}
