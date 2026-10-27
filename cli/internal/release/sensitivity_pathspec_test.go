package release

// STATBUS-532: DisplayPathspec feeds the git commands the stable preflight
// prints. It must be computed from the SAME rules the coverage check consults
// — the checked-in broad policy plus the home-specific rules — sorted,
// deduplicated, with prefix rules rendered as git wildcards and the arc
// own-file rules collapsed to their directory.

import (
	"strings"
	"testing"
)

func TestDisplayPathspec_ArcsFromPolicyAndHomeRules_STATBUS532(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())

	got, err := DisplayPathspec(dir, WorkflowArcs)
	if err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(got, " ")

	want := []string{
		// The broad policy, verbatim (prefix rendered as a git wildcard).
		"install.sh", "cli", "docker-compose.*", "dev.sh",
		"test/install-recovery/lib", "test/install-recovery/fixtures",
		"cli/internal/release", SensitivePathsFile,
		// The arc home's hard-coded rules (scenarioSensitivityRules).
		".github/workflows/upgrade-arc-harness.yaml",
		"test/install-recovery/run.sh",
		// Every arc's own-file rule collapses to the one directory.
		"test/install-recovery/arcs",
		// The two named arcs' extra harness inputs.
		"ops/ci-deploy-status.sh", "ops/niue/sshdo", "ops/niue/sshdoers",
	}
	for _, w := range want {
		if !strings.Contains(" "+joined+" ", " "+w+" ") {
			t.Errorf("pathspec missing %q; got: %s", w, joined)
		}
	}
	// Sorted and deduplicated: a path that several rules name appears once.
	for i := 1; i < len(got); i++ {
		if got[i-1] >= got[i] {
			t.Errorf("pathspec not sorted/deduplicated at %q, %q: %s", got[i-1], got[i], joined)
		}
	}
	// The collapse: no individual arc file may appear.
	if strings.Contains(joined, "-arc.sh") {
		t.Errorf("per-scenario own files must collapse to the arcs directory; got: %s", joined)
	}
}

func TestDisplayPathspec_SmokeKeepsItsExactScenarioFiles_STATBUS532(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())

	got, err := DisplayPathspec(dir, WorkflowSmoke)
	if err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(got, " ")
	for _, w := range []string{
		".github/workflows/test-smoke.yaml",
		"test/install-recovery/scenarios/0-happy-install.sh",
		"test/install-recovery/scenarios/0-happy-upgrade.sh",
		"test/install-recovery/run.sh",
	} {
		if !strings.Contains(" "+joined+" ", " "+w+" ") {
			t.Errorf("smoke pathspec missing %q; got: %s", w, joined)
		}
	}
	// The fixed two-scenario domain must NOT collapse to the directory:
	// smoke is sensitive to exactly these two files, not to siblings.
	if strings.Contains(joined, "test/install-recovery/scenarios ") || strings.HasSuffix(joined, "test/install-recovery/scenarios") {
		t.Errorf("smoke must name its exact scenario files, not the directory; got: %s", joined)
	}
}

func TestDisplayPathspec_RefusesNonScenarioHomes_STATBUS532(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())
	if _, err := DisplayPathspec(dir, WorkflowFleet); err == nil {
		t.Error("the historical fleet home has no live per-scenario check — a pathspec for it would invent display paths")
	}
}

// The pathspec must never claim a file is safe that the real check calls
// sensitive: every display path must match its own rule set. Spot-check the
// tricky ones through the real matcher.
func TestDisplayPathspec_NeverHidesASensitiveChange_STATBUS532(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())

	pathspec, err := DisplayPathspec(dir, WorkflowArcs)
	if err != nil {
		t.Fatal(err)
	}
	// For every sensitive path the real matcher reports for a generic arc,
	// some display entry must cover it as a git pathspec would (exact,
	// directory, or trailing-* prefix).
	covers := func(changedPath string) bool {
		for _, p := range pathspec {
			if strings.HasSuffix(p, "*") {
				if strings.HasPrefix(changedPath, strings.TrimSuffix(p, "*")) {
					return true
				}
				continue
			}
			if changedPath == p || strings.HasPrefix(changedPath, p+"/") {
				return true
			}
		}
		return false
	}
	for _, sensitivePath := range []string{
		"install.sh",
		"cli/cmd/upgrader.go",
		"docker-compose.yml",
		"dev.sh",
		"test/install-recovery/lib/provision.sh",
		"test/install-recovery/arcs/working-arc.sh",
		".github/workflows/upgrade-arc-harness.yaml",
		"test/install-recovery/run.sh",
		"cli/internal/release/coverage.go",
	} {
		if _, matched, err := MatchSensitivePath(dir, Scenario{Name: "working", Home: WorkflowArcs}, sensitivePath); err != nil || !matched {
			t.Fatalf("fixture broken: %s should be sensitive (matched=%v, err=%v)", sensitivePath, matched, err)
		}
		if !covers(sensitivePath) {
			t.Errorf("the printed pathspec would HIDE the sensitive change %s from the review commands", sensitivePath)
		}
	}
}
