package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// `./sb release covered <scenario> <commit>` — STATBUS-249.
//
// This is the SECOND call site of the coverage algorithm; the promotion gate is
// the first. The King's requirement was that they be the same "by design, not by
// chance", so both call release.DecideCoverage and both render its verdict.
// Neither owns a copy of the walk, which is what makes drift impossible rather
// than merely unlikely.
//
// It answers the question a chain job asks before spending machines: may this
// scenario be considered proven at this code-state? The answer distinguishes
// PROVEN HERE from COVERED BY <source> — a verdict that cannot tell those apart
// is exactly the bare success STATBUS-249 removes.
//
// EXIT CODES, chosen so a workflow can branch on them without parsing text:
//
//	0 — covered (proven here, or covered by a named source): the job may skip.
//	1 — NOT covered: the job must run.
//	2 — the question could not be answered after dispatch (API failure,
//	    unknown scenario, invalid commit).
//	    Distinct from 1 on purpose: "must run" is a decision, "could not tell"
//	    is a failure to decide, and a caller that conflates them would run the
//	    suite on every API hiccup while believing it had a verdict.
//
// Cobra command-line refusals exit 64 (EX_USAGE). Pre-dispatch binary
// refusals exit 69 (EX_UNAVAILABLE). Neither is a verdict; their constants
// live beside these verdict constants in exit_codes.go.

var releaseCoveredCmd = &cobra.Command{
	Use:   "covered <scenario> <commit>",
	Short: "Report whether a scenario is already proven at a commit (exit 0 covered, 1 must-run, 2 undecidable)",
	Long: "Report whether <scenario> is already proven at <commit>, either because it ran there\n" +
		"or because it is covered by an earlier code-state with nothing relevant changed since.\n\n" +
		"Uses the same decision as the promotion gate — one algorithm, two call sites.\n\n" +
		"Exit codes: 0 = covered (may skip), 1 = not covered (must run), 2 = could not decide.",
	Args: cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		scenario, commit := args[0], args[1]
		projDir := config.ProjectDir()

		verdict, err := decideScenarioCoverage(projDir, scenario, commit)
		if err != nil {
			// Undecidable is NOT "must run": say so, and exit 2.
			fmt.Fprintf(os.Stderr, "could not decide whether %s is covered at %s: %v\n", scenario, commit, err)
			os.Exit(exitUndecided)
		}

		fmt.Println(verdict.Summary())
		for _, e := range verdict.EvidenceErrors {
			// Surfaced, never swallowed: a walk that skipped candidates it
			// could not read must say so, or its "not covered" overstates
			// what it examined.
			fmt.Printf("  note: %s\n", e)
		}
		switch verdict.Kind {
		case release.CoverageCoveredBy:
			if verdict.AnchorDetail != "" {
				fmt.Printf("  evidence: %s\n", verdict.AnchorDetail)
			}
		case release.CoverageNotCovered:
			if verdict.BlockedBy != "" {
				fmt.Printf("  %s is proven, but %d file(s) that this scenario covers changed since then:\n",
					verdict.BlockedBy, len(verdict.ChangedPaths))
				for _, p := range verdict.ChangedPaths {
					fmt.Printf("    %s\n", p)
				}
			} else if n := len(verdict.EvidenceErrors); n > 0 {
				// "examined" must not overstate. Observed live: a run without a
				// token hit HTTP 403 on 7 of 20 candidates, and a bare "examined
				// 20" would have claimed a reading that never happened — the
				// exact overstatement this ticket exists to remove, one level down.
				fmt.Printf("  no evidence found — but %d of %d candidate(s) could NOT be read (see notes above), so this is 'not found', not 'not there'\n",
					n, verdict.CandidatesSeen)
			} else {
				fmt.Printf("  no evidence found in the %d candidate(s) examined\n", verdict.CandidatesSeen)
			}
		}

		if !verdict.Covered() {
			os.Exit(exitMustRun)
		}
		_ = exitCovered // returning nil IS exit 0; named so the contract reads in one place
		return nil
	},
}

// decideScenarioCoverage wires the real dependencies into the shared algorithm.
// Kept separate from the command so the wiring is testable without a process
// exit, and so the gate can adopt the identical construction.
func decideScenarioCoverage(projDir, name, commit string) (release.CoverageVerdict, error) {
	// Resolve to the FULL commit SHA first. GitHub's `head_sha=` query matches
	// the full object name only, so an abbreviated argument finds nothing at the
	// target and the walk then answers from a tag instead — reporting "covered
	// by <tag>" for a scenario that demonstrably RAN at the target itself.
	// Not unsafe, but a false account of where the proof came from, and this
	// command exists precisely to say where proof came from. Observed live:
	// `covered un-park-to-completion b4fd437fe` reported covered-by rc.05 when
	// the truth was proven-here.
	full, err := resolveCommitish(projDir, commit)
	if err != nil {
		return release.CoverageVerdict{}, fmt.Errorf("resolve %q to a commit: %w", commit, err)
	}
	commit = full

	sensitivePaths, err := loadUpgradeSensitivePaths(projDir)
	if err != nil {
		return release.CoverageVerdict{}, fmt.Errorf("load the sensitive-path list: %w", err)
	}

	// A bare name becomes a Scenario ONLY through the directory listing at this
	// commit, which is the same listing each promotion gate derives its domain
	// from. An unknown name is refused here rather than looked up under a
	// guessed workflow (which could only ever answer "not found").
	scenario, err := release.ParseScenario(projDir, commit, name)
	if err != nil {
		return release.CoverageVerdict{}, err
	}

	return release.DecideCoverage(scenario, commit, release.CoverageDeps{
		PriorCandidatesNewestFirst: func() ([]string, error) {
			return priorCandidateTags(projDir, commit)
		},
		TagCommit: func(tag string) (string, error) { return tagTargetCommit(projDir, tag) },
		Evidence:  scenarioEvidence(projDir, scenario),
		DiffTouches: func(from, to string) (bool, []string, error) {
			return diffTouchesSensitivePath(projDir, from, to, sensitivePaths)
		},
	})
}

// resolveCommitish expands any commit-ish (short SHA, tag, branch) to the full
// 40-character commit SHA the GitHub head_sha query requires.
func resolveCommitish(projDir, ref string) (string, error) {
	out, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", ref+"^{commit}")
	if err != nil {
		return "", err
	}
	full := strings.TrimSpace(out)
	if len(full) != 40 {
		return "", fmt.Errorf("git resolved %q to %q, which is not a full commit SHA", ref, full)
	}
	return full, nil
}

// priorCandidateTags lists RC tags STRICTLY OLDER than the candidate at commit,
// newest first — the walk's candidate list.
//
// When the target's own tag cannot be located (it may not be visible yet at
// check time), the whole RC list is returned newest-first rather than refusing.
// That matches the gate's existing defensive fallback: the target itself is
// answered by the direct-evidence check before the walk begins, so including it
// cannot manufacture a false inheritance.
func priorCandidateTags(projDir, commit string) ([]string, error) {
	tags, err := release.ReleaseTagsNewestFirst(projDir)
	if err != nil {
		return nil, err
	}
	var rcTags []string
	for _, t := range tags {
		if strings.Contains(t, "-rc.") {
			rcTags = append(rcTags, t)
		}
	}
	for i, t := range rcTags {
		if tagCommit, terr := tagTargetCommit(projDir, t); terr == nil && tagCommit == commit {
			return rcTags[i+1:], nil
		}
	}
	return rcTags, nil
}

func init() {
	releaseCmd.AddCommand(releaseCoveredCmd)
}
