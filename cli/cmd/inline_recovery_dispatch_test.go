package cmd

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// The real default executor and restoreSettingsBeforeDetect run here. Recovery,
// detection observations and the final claim are explicit integration boundaries.
func TestInlineRecoveryFreshDispatch(t *testing.T) {
	for _, scenario := range []string{"NoPriorOlderCLI", "StandingPark", "HealthyFreshDetection", "RecoveryError", "DetectError", "MissingSelected", "ChangedSelectedID", "ChangedSelectedSHA", "ChangedState", "RestoreSettingsError"} {
		t.Run(scenario, func(t *testing.T) {
			oldRecover, oldClaim, oldDetect := inlineDispatchReconcile, inlineDispatchClaim, detectInstallState
			oldRestore := restoreGeneratedSettings
			oldRestored := settingsRestoredBeforeDetect
			t.Cleanup(func() {
				inlineDispatchReconcile = oldRecover
				inlineDispatchClaim = oldClaim
				detectInstallState = oldDetect
				restoreGeneratedSettings = oldRestore
				settingsRestoredBeforeDetect = oldRestored
			})
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("# owned synthetic route\n"), 0600); err != nil {
				t.Fatal(err)
			}
			detail := scheduledDetail()
			if scenario == "RestoreSettingsError" {
				if err := os.Remove(filepath.Join(dir, ".env")); err != nil {
					t.Fatal(err)
				}
				for _, name := range []string{".env.config", ".env.credentials"} {
					if err := os.WriteFile(filepath.Join(dir, name), nil, 0600); err != nil {
						t.Fatal(err)
					}
				}
				restoreGeneratedSettings = func(string) error { return errors.New("owned settings restore failure") }
			}
			detections, claims := 0, 0
			var fresh *install.Detail
			inlineDispatchReconcile = func(_ context.Context, _ *upgrade.Service, after func(string) error) error {
				if scenario == "NoPriorOlderCLI" || scenario == "StandingPark" {
					return nil
				}
				if scenario == "RecoveryError" {
					return errors.New("owned restore/convergence refusal")
				}
				return after(dir)
			}
			detectInstallState = func(project, current string) (install.State, *install.Detail, error) {
				detections++
				if project != dir {
					t.Fatal("wrong restored project")
				}
				if scenario == "DetectError" {
					return 0, nil, errors.New("owned fresh detection read error")
				}
				copy := *detail
				fresh = &copy
				state := install.StateScheduledUpgrade
				switch scenario {
				case "MissingSelected":
					fresh = nil
				case "ChangedSelectedID":
					fresh.ScheduledRowID++
				case "ChangedSelectedSHA":
					fresh.TargetCommitSHA = "1007000000000000000000000000000000000001"
				case "ChangedState":
					state = install.StateNothingScheduled
				}
				return state, fresh, nil
			}
			inlineDispatchClaim = func(_ context.Context, _ *upgrade.Service, id int, sha, name string) error {
				claims++
				if id != int(detail.ScheduledRowID) || sha != detail.TargetCommitSHA || name != detail.TargetDisplayName {
					t.Fatal("selected identity changed")
				}
				return nil
			}
			// Different current executable and future target are normal, not a refusal.
			svc := upgrade.NewService(dir, false, "older CLI", "1007000000000000000000000000000000000001")
			err := inlineDispatchExecute(context.Background(), svc, int(detail.ScheduledRowID), detail.TargetCommitSHA, detail.TargetDisplayName)
			normal := scenario == "NoPriorOlderCLI" || scenario == "StandingPark" || scenario == "HealthyFreshDetection"
			if normal {
				if err != nil || claims != 1 {
					t.Fatalf("normal path rejected: err=%v claims=%d", err, claims)
				}
			} else if err == nil || claims != 0 {
				t.Fatalf("refusal reached claim: err=%v claims=%d", err, claims)
			}
			if scenario == "NoPriorOlderCLI" || scenario == "StandingPark" || scenario == "RecoveryError" || scenario == "RestoreSettingsError" {
				if detections != 0 {
					t.Fatal("ordinary/refused recovery unexpectedly re-detected")
				}
			} else if detections != 1 {
				t.Fatal("fresh detection not observed exactly once")
			}
			if scenario == "RecoveryError" && !strings.Contains(err.Error(), "restore/convergence refusal") {
				t.Fatal("recovery failure cause lost")
			}
			t.Logf("real caller: scenario=%s detections=%d claims=%d error=%v", scenario, detections, claims, err)
		})
	}
}
