package cmd

import (
	"errors"
	"os/exec"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
)

// STATBUS-382: while ./sb install holds the upgrade lock it stops the
// upgrader before any install step runs. A successful install starts it again
// on the installed ./sb; a failed install leaves it stopped and says so.
// The operator sees install output through ops/install-terminal-output.awk;
// both upgrader lines reach the screen unchanged.
func TestInstallUpgraderStopLinesReachTheOperator(t *testing.T) {
	lines := []string{
		"Stopping the upgrader while the installation runs; it starts again when the installation succeeds.",
		upgraderStoppedForInstallNotice("/home/statbus/statbus"),
	}
	input := strings.Join(lines, "\n") + "\n"
	cmd := exec.Command("awk", "-f", "../../ops/install-terminal-output.awk")
	cmd.Stdin = strings.NewReader(input)
	got, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != input {
		t.Fatalf("terminal shows:\n%s\nwant:\n%s", got, input)
	}
}

// rc.04 gate (smoke 41158823385, 0-happy-install): a green-box rerun must
// report every step OK. The install stops the upgrader before the steps, so
// the Upgrader step sees the unit inactive; that step is done when this
// install stopped a correct unit itself, and still runs when the upgrader was
// simply not running.
func TestUpgraderStepDoneWhenThisInstallStoppedIt(t *testing.T) {
	cases := []struct {
		state   unitfloor.State
		stopped bool
		want    bool
	}{
		{unitfloor.OK, false, true},
		{unitfloor.Inactive, true, true},
		{unitfloor.Inactive, false, false},
		{unitfloor.UnitFileDrifted, true, false},
		{unitfloor.UnitFileMissing, true, false},
		{unitfloor.NotApplicable, false, true},
	}
	for _, c := range cases {
		if got := upgraderStepDone(c.state, c.stopped); got != c.want {
			t.Errorf("upgraderStepDone(%v, stopped=%v) = %v, want %v", c.state, c.stopped, got, c.want)
		}
	}
}

func TestInstallStopsUpgraderUnderLockAndStartsItOnlyOnSuccess(t *testing.T) {
	cases := []struct {
		name        string
		running     bool
		fixup       bool
		stepErr     error
		wantStop    bool
		wantStart   bool
		wantStopped string
	}{
		{name: "running upgrader, install succeeds", running: true, wantStop: true, wantStart: true},
		{name: "running upgrader, install fails", running: true, stepErr: errors.New("step failed"), wantStop: true, wantStopped: "The upgrader stays stopped until the installation finishes successfully: cd "},
		{name: "upgrader not running", running: false},
		{name: "upgrader's own post-upgrade install", running: true, fixup: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			withRunInstallDetectionHooks(t)
			t.Setenv("USER", "statbus")
			sysd := installFakeSystemd(t)
			origPlatform := installServicePlatform
			installServicePlatform = "linux"
			t.Cleanup(func() { installServicePlatform = origPlatform })
			instance := unitfloor.InstanceName("statbus")
			u := sysd.unit(instance)
			u.loadState = "loaded"
			u.enabled = "enabled"
			if tc.running {
				u.activeState = "active"
				u.mainPID = 4242
			}
			postUpgradeFixup = tc.fixup
			detectInstallState = func(string, string) (install.State, *install.Detail, error) {
				return install.StateNothingScheduled, &install.Detail{}, nil
			}
			var activeWhenStepsRan string
			runInstallStepTableTestHook = func() error {
				activeWhenStepsRan = sysd.unit(instance).activeState
				return tc.stepErr
			}
			var dispatched []upgradeDaemonFinalAction
			origDispatch := dispatchUpgradeDaemonFinalAction
			dispatchUpgradeDaemonFinalAction = func(_ string, a upgradeDaemonFinalAction) error {
				dispatched = append(dispatched, a)
				return nil
			}
			t.Cleanup(func() { dispatchUpgradeDaemonFinalAction = origDispatch })

			out := captureStdout(t, func() {
				err := runInstall()
				if (err != nil) != (tc.stepErr != nil) {
					t.Fatalf("runInstall err = %v, want error %v", err, tc.stepErr != nil)
				}
			})

			stopped := u.stopCalls > 0
			if stopped != tc.wantStop {
				t.Fatalf("upgrader stopped = %v, want %v (calls %v)", stopped, tc.wantStop, sysd.calls)
			}
			if tc.wantStop && activeWhenStepsRan != "inactive" {
				t.Fatalf("install steps ran while the upgrader was %q; it must be stopped first", activeWhenStepsRan)
			}
			started := len(dispatched) == 1 && dispatched[0] == upgradeDaemonStart
			if started != tc.wantStart {
				t.Fatalf("final upgrader actions = %v, want start=%v", dispatched, tc.wantStart)
			}
			if !tc.wantStart && len(dispatched) != 0 {
				t.Fatalf("final upgrader actions = %v, want none", dispatched)
			}
			if tc.wantStopped != "" && !strings.Contains(out, tc.wantStopped) {
				t.Fatalf("output does not say the upgrader stays stopped:\n%s", out)
			}
			if tc.wantStopped == "" && strings.Contains(out, "stays stopped") {
				t.Fatalf("output claims the upgrader stays stopped:\n%s", out)
			}
		})
	}
}
