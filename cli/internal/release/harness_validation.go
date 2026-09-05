package release

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// harnessTreePath is the one directory the install-recovery runner and its
// scenario/arc domain live under. Only this subtree is extracted for
// validation: the runner's --print-selected path reads nothing outside it.
const harnessTreePath = "test/install-recovery"

// ValidateHarnessDomainAt runs the target commit's OWN authoritative
// install-recovery domain validation (`run.sh --print-selected`) against a
// disposable extraction of that commit's harness tree, and checks that the
// scenario list it emits is exactly the Fleet domain ScenariosAt derives.
//
// WHY THIS EXISTS (STATBUS-352 Work A review, finding 1): the runner's
// structural guard — no `fabricate_*` calls, no direct `public.upgrade`
// writes, across EVERY scenario and arc — was only a workflow shell step. The
// shared coverage evaluator behind `release covered`, `covered-subset`, and
// stable promotion never ran it, so an excluded (HARNESS_SKIP_DEFAULT)
// sibling could gain a forbidden construct and every required scenario could
// still be reported "covered": the runner would have refused the repository,
// but promotion authority said yes. Making this a prerequisite of the shared
// evaluator closes that gap in ONE place.
//
// The doctrine itself is NOT re-implemented here. The extracted tree's run.sh
// is executed as the single validator, exactly as the discover jobs do. The
// working tree is never read or mutated; `git archive` streams the committed
// tree into a temp dir that is removed before return.
//
// Any failure — extraction, a missing or non-executable runner, a validator
// refusal, empty output, or a domain that disagrees with ScenariosAt — is an
// ERROR, never "validated". The callers turn that into an undecidable
// coverage question (covered-subset exits 2 with no partial stdout so the
// orchestrator dispatches the full suite; stable promotion refuses).
func ValidateHarnessDomainAt(projDir, commit string) error {
	if commit == "" {
		return fmt.Errorf("harness domain validation needs a target commit")
	}
	expected, err := fleetAt(projDir, commit)
	if err != nil {
		return fmt.Errorf("derive the fleet domain at %s: %w", shortSHA(commit), err)
	}

	tmp, err := os.MkdirTemp("", "statbus-harness-validate-")
	if err != nil {
		return fmt.Errorf("create a disposable extraction dir: %w", err)
	}
	defer func() { _ = os.RemoveAll(tmp) }()

	if err := extractHarnessTree(projDir, commit, tmp); err != nil {
		return err
	}

	runner := filepath.Join(tmp, harnessTreePath, "run.sh")
	if info, statErr := os.Stat(runner); statErr != nil || info.IsDir() {
		return fmt.Errorf("%s has no %s/run.sh to validate the harness domain with: %v", shortSHA(commit), harnessTreePath, statErr)
	}

	cmd := exec.Command("bash", runner, "--print-selected")
	cmd.Dir = tmp
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("the harness domain at %s failed its own structural validation (run.sh --print-selected): %w\n%s",
			shortSHA(commit), err, strings.TrimSpace(stderr.String()))
	}

	var got []string
	for _, line := range strings.Split(strings.TrimSpace(stdout.String()), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			got = append(got, line)
		}
	}
	if len(got) == 0 {
		return fmt.Errorf("run.sh --print-selected at %s emitted no scenarios — refusing an empty validated domain", shortSHA(commit))
	}
	sort.Strings(got)
	want := make([]string, 0, len(expected.Scenarios))
	for _, s := range expected.Scenarios {
		want = append(want, s.Name)
	}
	sort.Strings(want)
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		return fmt.Errorf("run.sh --print-selected at %s selected %v but the coverage domain derived %v — the runner and the evaluator disagree about the fleet domain",
			shortSHA(commit), got, want)
	}
	return nil
}

// extractHarnessTree materialises commit:test/install-recovery under dest via
// `git archive | tar`, the only historical-tree read this needs. No worktree,
// no checkout, no working-tree mutation.
func extractHarnessTree(projDir, commit, dest string) error {
	archive := exec.Command("git", "archive", "--format=tar", commit, "--", harnessTreePath)
	archive.Dir = projDir
	archive.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	var archiveErr bytes.Buffer
	archive.Stderr = &archiveErr

	untar := exec.Command("tar", "-x", "-C", dest)
	var untarErr bytes.Buffer
	untar.Stderr = &untarErr
	pipe, err := archive.StdoutPipe()
	if err != nil {
		return fmt.Errorf("git archive pipe: %w", err)
	}
	untar.Stdin = pipe

	if err := untar.Start(); err != nil {
		return fmt.Errorf("start tar: %w", err)
	}
	if err := archive.Run(); err != nil {
		_ = untar.Wait()
		return fmt.Errorf("git archive %s -- %s: %w: %s", shortSHA(commit), harnessTreePath, err, strings.TrimSpace(archiveErr.String()))
	}
	if err := untar.Wait(); err != nil {
		return fmt.Errorf("extract %s -- %s: %w: %s", shortSHA(commit), harnessTreePath, err, strings.TrimSpace(untarErr.String()))
	}
	return nil
}
