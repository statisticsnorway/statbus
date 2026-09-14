package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func TestRestartOwnsCompleteWorkflow(t *testing.T) {
	for _, tc := range []struct {
		name, profile, state, fail string
		systemd                    bool
		want                       []string
		bad                        bool
	}{
		{"all", "all", "active", "", true, []string{"show", "stop", "stack:all", "start"}, false},
		{"all except app", "all_except_app", "active", "", true, []string{"show", "stop", "stack:all_except_app", "start"}, false},
		{"app narrow", "app", "active", "", true, []string{"stack:app"}, false},
		{"non systemd", "all", "active", "", false, []string{"stack:all"}, false},
		{"inactive preserved", "all", "inactive", "", true, []string{"show", "stack:all"}, false},
		{"missing unit", "all", "missing", "", true, []string{"show", "stack:all"}, false},
		{"failed unit refuses", "all", "failed", "", true, []string{"show"}, true},
		{"probe failure", "all", "active", "show", true, []string{"show"}, true},
		{"stop failure", "all", "active", "stop", true, []string{"show", "stop", "start"}, true},
		{"stack failure restores daemon", "all", "active", "stack", true, []string{"show", "stop", "stack:all", "start"}, true},
		{"start failure propagates", "all", "active", "start", true, []string{"show", "stop", "stack:all", "start"}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			var calls []string
			ops := restartOperations{systemd: tc.systemd, unit: "statbus-upgrade@test.service"}
			ops.systemctl = func(args ...string) (string, error) {
				action := args[0]
				calls = append(calls, action)
				if held := upgrade.IsFlockHeld(dir); !held {
					t.Fatalf("%s: held=%v", action, held)
				}
				if action == tc.fail {
					return "fixture failure", errors.New(tc.fail)
				}
				if action == "show" {
					if tc.state == "missing" {
						return "LoadState=not-found\nActiveState=inactive\n", nil
					}
					return "LoadState=loaded\nActiveState=" + tc.state + "\n", nil
				}
				return "", nil
			}
			ops.stack = func(profile string) error {
				calls = append(calls, "stack:"+profile)
				if !upgrade.IsFlockHeld(dir) {
					t.Fatal("stack restart without kernel mutex")
				}
				if other, err := upgrade.AcquireInstallFlag(dir, "racer"); err == nil {
					upgrade.ReleaseInstallFlag(other)
					t.Fatal("concurrent upgrade/install could enter")
				}
				if tc.fail == "stack" {
					return errors.New("stack failed")
				}
				return nil
			}
			err := restartServicesWith(dir, tc.profile, ops)
			if (err != nil) != tc.bad {
				t.Fatalf("err=%v", err)
			}
			if !reflect.DeepEqual(calls, tc.want) {
				t.Fatalf("calls=%v want=%v", calls, tc.want)
			}
			_, statErr := os.Stat(filepath.Join(dir, "tmp", "upgrade-in-progress.json"))
			retained := tc.fail == "stop" || tc.fail == "stack" || tc.fail == "start"
			if retained && statErr != nil {
				t.Fatalf("failed restart intent lost: %v", statErr)
			}
			if !retained && !os.IsNotExist(statErr) {
				t.Fatalf("unexpected marker: %v", statErr)
			}
		})
	}
}

func TestRestartRefusesLiveAndStaleIntentBeforeDisruption(t *testing.T) {
	for _, kind := range []string{"live", "stale-service", "stale-install", "malformed"} {
		t.Run(kind, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
			if kind == "live" {
				lock, err := upgrade.AcquireInstallFlag(dir, "other operation")
				if err != nil {
					t.Fatal(err)
				}
				defer upgrade.ReleaseInstallFlag(lock)
			} else {
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				data := `{"holder":"service","id":17,"phase":"new_sb_upgrading"}`
				if kind == "stale-install" {
					data = `{"holder":"install"}`
				}
				if kind == "malformed" {
					data = "incomplete recovery marker"
				}
				if err := os.WriteFile(path, []byte(data), 0600); err != nil {
					t.Fatal(err)
				}
			}
			before, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			ops := restartOperations{systemd: true, unit: "unit", systemctl: func(...string) (string, error) { t.Fatal("systemd reached on refusal"); return "", nil }, stack: func(string) error { t.Fatal("stack reached on refusal"); return nil }}
			err = restartServicesWith(dir, "all", ops)
			if err == nil || !strings.Contains(err.Error(), "No services were stopped") {
				t.Fatalf("refusal: %v", err)
			}
			after, _ := os.ReadFile(path)
			if string(before) != string(after) {
				t.Fatal("recovery intent was overwritten")
			}
		})
	}
}

func TestRestartReportsStackAndDaemonFailures(t *testing.T) {
	dir := t.TempDir()
	ops := restartOperations{systemd: true, unit: "unit", systemctl: func(args ...string) (string, error) {
		if args[0] == "show" {
			return "LoadState=loaded\nActiveState=active\n", nil
		}
		if args[0] == "start" {
			return "", errors.New("daemon error")
		}
		return "", nil
	}, stack: func(string) error { return errors.New("stack error") }}
	err := restartServicesWith(dir, "all", ops)
	if err == nil || !strings.Contains(err.Error(), "stack error") || !strings.Contains(err.Error(), "daemon error") {
		t.Fatalf("lost error: %v", err)
	}
}

func TestRestartRetryPreservesIntentAndExcludesInstall(t *testing.T) {
	for _, active := range []bool{false, true} {
		t.Run(map[bool]string{false: "inactive", true: "active"}[active], func(t *testing.T) {
			dir := t.TempDir()
			first := true
			var starts int
			ops := restartOperations{systemd: true, unit: "unit", systemctl: func(args ...string) (string, error) {
				if !upgrade.IsFlockHeld(dir) {
					t.Fatal("unprotected daemon operation")
				}
				if args[0] == "show" {
					if active {
						return "LoadState=loaded\nActiveState=active\n", nil
					}
					return "LoadState=loaded\nActiveState=inactive\n", nil
				}
				if args[0] == "start" {
					starts++
				}
				return "", nil
			}, stack: func(string) error {
				if !upgrade.IsFlockHeld(dir) {
					t.Fatal("unprotected stack")
				}
				if lock, _, err := upgrade.AcquireRestartFlag(dir, "all"); err == nil {
					lock.Close()
					t.Fatal("concurrent retry entered")
				}
				if first {
					return errors.New("stack failure")
				}
				return nil
			}}
			if err := restartServicesWith(dir, "all", ops); err == nil {
				t.Fatal("failure hidden")
			}
			if err := upgrade.CheckRestartBarrier(dir); err == nil {
				t.Fatal("install probe not gated")
			}
			if lock, err := upgrade.AcquireInstallFlag(dir, "racing install"); err == nil {
				lock.Close()
				t.Fatal("install erased barrier")
			}
			if err := restartServicesWith(dir, "app", ops); err == nil {
				t.Fatal("wrong retry profile accepted")
			}
			first = false
			if err := restartServicesWith(dir, "all", ops); err != nil {
				t.Fatal(err)
			}
			if err := upgrade.CheckRestartBarrier(dir); err != nil {
				t.Fatal(err)
			}
			if active && starts != 2 {
				t.Fatalf("starts=%d", starts)
			}
			if !active && starts != 0 {
				t.Fatalf("inactive daemon resurrected %d times", starts)
			}
		})
	}
}

func TestInstallRefusesRestartBeforeProbes(t *testing.T) {
	home, _ := unattendedFixture(t)
	t.Setenv("HOME", home)
	t.Setenv("STATBUS_POST_UPGRADE_FIXUP", "")
	dir := filepath.Join(home, "statbus")
	lock, _, err := upgrade.AcquireRestartFlag(dir, "all")
	if err != nil {
		t.Fatal(err)
	}
	if err := upgrade.PrepareRestart(lock, upgrade.RestartIntent{Profile: "all"}); err != nil {
		t.Fatal(err)
	}
	lock.Close()
	err = runInstall()
	if err == nil || !strings.Contains(err.Error(), "./sb restart all") {
		t.Fatalf("install: %v", err)
	}
}
