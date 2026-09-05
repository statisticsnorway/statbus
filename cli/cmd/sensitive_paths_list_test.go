package cmd

import (
	"path/filepath"
	"runtime"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// The real checked policy contains only rules broad across every paid home.
// Scenario directories must never reappear as broad directory rules because
// that would make sibling contents sensitive again.
func TestUpgradeSensitivePolicyReachesBroadInputsWithoutRebroadeningSiblings_STATBUS352(t *testing.T) {
	_, here, _, _ := runtime.Caller(0)
	projDir := filepath.Clean(filepath.Join(filepath.Dir(here), "..", ".."))
	if err := release.ValidateSensitivityPolicy(projDir); err != nil {
		t.Fatalf("loading real sensitivity policy: %v", err)
	}

	homes := []release.Scenario{
		{Name: "0-happy-install", Home: release.WorkflowSmoke},
		{Name: "0-happy-install", Home: release.WorkflowFleet},
		{Name: "working", Home: release.WorkflowArcs},
	}
	broad := map[string]release.SensitivityReason{
		"install.sh":                                            release.ReasonBoxPayload,
		"cli/cmd/install.go":                                    release.ReasonBoxPayload,
		"cli/internal/upgrade/service.go":                       release.ReasonBoxPayload,
		"docker-compose.worker.yml":                             release.ReasonBoxPayload,
		"caddy/templates/x.caddyfile.tmpl":                      release.ReasonBoxPayload,
		"migrations/20260101000000_x.up.sql":                    release.ReasonBoxPayload,
		"postgres/Dockerfile":                                   release.ReasonBoxPayload,
		"dev.sh":                                                release.ReasonSharedController,
		".github/workflows/release-fleet-orchestrator.yaml":     release.ReasonSharedController,
		".github/actions/dispatch-fleet-and-wait/dispatch.sh":   release.ReasonSharedController,
		".github/actions/orchestrator-fleet-admission/admit.sh": release.ReasonSharedController,
		".github/workflows/images.yaml":                         release.ReasonSharedController,
		"ops/setup-ubuntu-lts-24.sh":                            release.ReasonSharedHarnessInput,
		"test/install-recovery/lib/vm-bootstrap.sh":             release.ReasonSharedHarnessInput,
		"test/install-recovery/fixtures/stage-head.sh":          release.ReasonSharedHarnessInput,
		"cli/internal/release/sensitivity.go":                   release.ReasonProofInterpreter,
		"cli/cmd/release/release_covered.go":                    release.ReasonProofInterpreter,
		"cli/cmd/release/release_coverage_evaluator.go":         release.ReasonProofInterpreter,
		"ops/release/upgrade-sensitive-paths.txt":               release.ReasonProofInterpreter,
	}
	for _, scenario := range homes {
		for file, wantReason := range broad {
			change, matched, err := release.MatchSensitivePath(projDir, scenario, file)
			if err != nil {
				t.Fatalf("%v %s: %v", scenario, file, err)
			}
			if !matched || change.Reason != wantReason {
				t.Errorf("%v %s: matched=%v reason=%q, want %q", scenario, file, matched, change.Reason, wantReason)
			}
		}
	}

	fleetA := release.Scenario{Name: "0-happy-install", Home: release.WorkflowFleet}
	for _, sibling := range []string{
		"test/install-recovery/scenarios/0-happy-upgrade.sh",
		"test/install-recovery/arcs/working-arc.sh",
	} {
		if _, matched, err := release.MatchSensitivePath(projDir, fleetA, sibling); err != nil {
			t.Fatal(err)
		} else if matched {
			t.Errorf("sibling %s became broad again", sibling)
		}
	}

	for _, file := range []string{"app/src/app/page.tsx", "doc/CLOUD.md", "README.md", "tools/cli/example.go", "x/docker-compose.yml"} {
		if _, matched, err := release.MatchSensitivePath(projDir, fleetA, file); err != nil {
			t.Fatal(err)
		} else if matched {
			t.Errorf("%s unexpectedly matched the real sensitivity policy", file)
		}
	}
}
