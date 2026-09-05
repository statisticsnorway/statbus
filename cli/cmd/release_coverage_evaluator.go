package cmd

import (
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// coverageEvaluator is the one production wiring for release.DecideCoverage.
// Stable promotion, `release covered`, and `covered-subset` all call Decide, so
// scenario evidence, candidate order, and scenario-aware sensitivity cannot drift.
type coverageEvaluator struct {
	projDir string
	commit  string

	candidates       []string
	candidatesErr    error
	candidatesLoaded bool
}

func newCoverageEvaluator(projDir, commitish string) (*coverageEvaluator, error) {
	commit, err := resolveCommitish(projDir, commitish)
	if err != nil {
		return nil, fmt.Errorf("resolve %q to a commit: %w", commitish, err)
	}
	if err := release.ValidateSensitivityPolicy(projDir); err != nil {
		return nil, fmt.Errorf("load the sensitivity policy: %w", err)
	}
	// The target commit's harness tree must pass its OWN structural
	// validation before any coverage answer exists (STATBUS-352 Work A review,
	// finding 1). Without this, a forbidden construct in an excluded sibling
	// could leave every required scenario "covered" while the runner would
	// refuse the repository. An error here is an undecidable question for every
	// caller: covered-subset fails open to the full suite, promotion refuses.
	if err := release.ValidateHarnessDomainAt(projDir, commit); err != nil {
		return nil, fmt.Errorf("structural validation of the install-recovery domain at %s: %w", commit[:9], err)
	}
	return &coverageEvaluator{projDir: projDir, commit: commit}, nil
}

func (e *coverageEvaluator) priorCandidates() ([]string, error) {
	if !e.candidatesLoaded {
		e.candidates, e.candidatesErr = priorCandidateTags(e.projDir, e.commit)
		e.candidatesLoaded = true
	}
	return e.candidates, e.candidatesErr
}

func (e *coverageEvaluator) Decide(scenario release.Scenario) (release.CoverageVerdict, error) {
	return release.DecideCoverage(scenario, e.commit, release.CoverageDeps{
		PriorCandidatesNewestFirst: e.priorCandidates,
		TagCommit:                  func(tag string) (string, error) { return tagTargetCommit(e.projDir, tag) },
		Evidence:                   scenarioEvidence(e.projDir, scenario),
		DiffSensitive: func(from, to string) ([]release.SensitiveChange, error) {
			return release.DiffSensitiveChanges(e.projDir, from, to, scenario)
		},
	})
}

func (e *coverageEvaluator) Scenario(name string, workflow release.Workflow) (release.Scenario, error) {
	if workflow != "" {
		return release.ScenarioAt(e.projDir, e.commit, name, workflow)
	}
	return release.ParseScenario(e.projDir, e.commit, name)
}

func (e *coverageEvaluator) Domain(workflow release.Workflow) (release.Domain, error) {
	return release.ScenariosAt(e.projDir, e.commit, workflow)
}
