package release

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeSensitivityPolicy(t *testing.T, dir, content string) {
	t.Helper()
	full := filepath.Join(dir, SensitivePathsFile)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func testPolicy() string {
	return strings.Join([]string{
		"exact | box payload | install.sh",
		"directory | box payload | cli",
		"prefix | box payload | docker-compose.",
		"exact | shared controller | dev.sh",
		"directory | shared harness input | test/install-recovery/lib",
		"directory | shared harness input | test/install-recovery/fixtures",
		"directory | proof interpreter | cli/internal/release",
		"exact | proof interpreter | ops/release/upgrade-sensitive-paths.txt",
	}, "\n") + "\n"
}

func TestSensitivityPolicy_AnchoredExactDirectoryAndPrefix_STATBUS352(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())
	scenario := fleet("scenario-a")

	cases := []struct {
		path   string
		match  bool
		reason SensitivityReason
	}{
		{"install.sh", true, ReasonBoxPayload},
		{"doc/install.sh-notes", false, ""},
		{"cli/cmd/install.go", true, ReasonBoxPayload},
		{"tools/cli/example.go", false, ""},
		{"cli2/file.go", false, ""},
		{"docker-compose.worker.yml", true, ReasonBoxPayload},
		{"x/docker-compose.yml", false, ""},
		{"docker-compose-old.yml", false, ""},
	}
	for _, tc := range cases {
		change, matched, err := MatchSensitivePath(dir, scenario, tc.path)
		if err != nil {
			t.Fatalf("%s: %v", tc.path, err)
		}
		if matched != tc.match || change.Reason != tc.reason {
			t.Errorf("%s: got matched=%v reason=%q, want %v %q", tc.path, matched, change.Reason, tc.match, tc.reason)
		}
	}
}

func TestSensitivityPolicy_RefusesEmptyMalformedAndUnsafeRules_STATBUS352(t *testing.T) {
	for name, content := range map[string]string{
		"empty":      "# comments only\n",
		"old format": "cli/\n",
		"unknown":    "glob | box payload | cli\n",
		"traversal":  "exact | box payload | ../install.sh\n",
		"reason":     "exact | something else | install.sh\n",
	} {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			writeSensitivityPolicy(t, dir, content)
			if err := ValidateSensitivityPolicy(dir); err == nil {
				t.Fatal("invalid policy was accepted")
			}
		})
	}
}

func TestMatchSensitivePath_UsesFullScenarioHomeAndOwnScript_STATBUS352(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())
	fleetA := fleet("scenario-a")
	smokeInstall := Scenario{Name: "0-happy-install", Home: WorkflowSmoke}

	cases := []struct {
		name     string
		scenario Scenario
		path     string
		match    bool
		reason   SensitivityReason
	}{
		{"fleet own", fleetA, "test/install-recovery/scenarios/scenario-a.sh", true, ReasonOwnScenario},
		{"fleet sibling", fleetA, "test/install-recovery/scenarios/scenario-b.sh", false, ""},
		{"backup is not own", fleetA, "test/install-recovery/scenarios/scenario-a.sh.backup", false, ""},
		{"fleet runner", fleetA, "test/install-recovery/run.sh", true, ReasonSharedController},
		{"fleet workflow", fleetA, ".github/workflows/install-recovery-harness.yaml", true, ReasonSharedController},
		{"fleet ignores smoke wrapper", fleetA, ".github/workflows/test-smoke.yaml", false, ""},
		{"smoke own", smokeInstall, "test/install-recovery/scenarios/0-happy-install.sh", true, ReasonOwnScenario},
		{"smoke ignores runner", smokeInstall, "test/install-recovery/run.sh", false, ""},
		{"smoke workflow", smokeInstall, ".github/workflows/test-smoke.yaml", true, ReasonSharedController},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			change, matched, err := MatchSensitivePath(dir, tc.scenario, tc.path)
			if err != nil {
				t.Fatal(err)
			}
			if matched != tc.match || change.Reason != tc.reason {
				t.Fatalf("got matched=%v reason=%q, want %v %q", matched, change.Reason, tc.match, tc.reason)
			}
		})
	}
}

func TestMatchSensitivePath_SharedInputsArcHelpersProofAndBroadCLI_STATBUS352(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())

	cases := []struct {
		scenario Scenario
		path     string
		match    bool
		reason   SensitivityReason
	}{
		{fleet("a"), "test/install-recovery/lib/assertions.sh", true, ReasonSharedHarnessInput},
		{Scenario{Name: "0-happy-upgrade", Home: WorkflowSmoke}, "test/install-recovery/fixtures/stage-head.sh", true, ReasonSharedHarnessInput},
		{arc("failing"), "ops/ci-deploy-status.sh", true, ReasonSharedHarnessInput},
		{arc("deploy-status-proof"), "ops/ci-deploy-status.sh", true, ReasonSharedHarnessInput},
		{arc("working"), "ops/ci-deploy-status.sh", false, ""},
		{arc("deploy-status-proof"), "ops/niue/sshdo", true, ReasonSharedHarnessInput},
		{arc("deploy-status-proof"), "ops/niue/sshdoers", true, ReasonSharedHarnessInput},
		{arc("deploy-status-proof"), "ops/niue/sshdo-not-used", false, ""},
		{fleet("a"), "cli/internal/upgrade/service.go", true, ReasonBoxPayload},
		{fleet("a"), "cli/internal/release/sensitivity.go", true, ReasonProofInterpreter},
		{fleet("a"), SensitivePathsFile, true, ReasonProofInterpreter},
	}
	for _, tc := range cases {
		change, matched, err := MatchSensitivePath(dir, tc.scenario, tc.path)
		if err != nil {
			t.Fatalf("%s: %v", tc.path, err)
		}
		if matched != tc.match || change.Reason != tc.reason {
			t.Errorf("%v %s: got matched=%v reason=%q, want %v %q", tc.scenario, tc.path, matched, change.Reason, tc.match, tc.reason)
		}
	}
}

func TestMatchSensitivePath_RejectsUndecidableScenarioAndPath_STATBUS352(t *testing.T) {
	dir := t.TempDir()
	writeSensitivityPolicy(t, dir, testPolicy())
	for _, scenario := range []Scenario{
		{Name: "../escape", Home: WorkflowFleet},
		{Name: "0-happy-install", Home: "unknown.yaml"},
		{Name: "not-a-smoke", Home: WorkflowSmoke},
	} {
		if _, _, err := MatchSensitivePath(dir, scenario, "install.sh"); err == nil {
			t.Errorf("scenario %+v was accepted", scenario)
		}
	}
	for _, changedPath := range []string{"/absolute", "./install.sh", "../install.sh", "a/../install.sh"} {
		if _, _, err := MatchSensitivePath(dir, fleet("a"), changedPath); err == nil {
			t.Errorf("path %q was accepted", changedPath)
		}
	}
}
