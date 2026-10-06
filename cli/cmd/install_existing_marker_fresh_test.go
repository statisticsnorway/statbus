package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/installinput"
)

// Exercise the actual interrupted first-install route without services or DB.
func TestExistingInstallBeforeConfigReusesInheritedLock(t *testing.T) {
	for _, scenario := range []string{"success", "step-error", "input-refusal", "service-intent"} {
		t.Run(scenario, func(t *testing.T) {
			failStep := scenario == "step-error"
			earlyRefusal := scenario == "input-refusal" || scenario == "service-intent"
			stepError := errors.New("first-step fixture refusal")
			dir := withRunInstallDetectionHooks(t)
			if err := os.Remove(filepath.Join(dir, ".env.config")); err != nil {
				t.Fatal(err)
			}
			answers := filepath.Join(t.TempDir(), "answers.env")
			input := "CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\nDEPLOYMENT_SLOT_NAME=Review\nDEPLOYMENT_SLOT_CODE=local\nTRUST_GITHUB_USER=jhf\n"
			if err := os.WriteFile(answers, []byte(input), 0600); err != nil {
				t.Fatal(err)
			}
			t.Setenv(installinput.EnvConfig, answers)
			t.Setenv(installinput.UsersFile, "")
			t.Setenv("STATBUS_POST_UPGRADE_FIXUP", "")
			path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
			if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
				t.Fatal(err)
			}
			marker := []byte(`{"id":0,"holder":"install","trigger":"install","invoked_by":"install.sh:review"}`)
			if scenario == "service-intent" {
				marker = []byte(`{"id":7,"holder":"service","trigger":"install-cli","phase":"backing_up"}`)
			}
			if err := os.WriteFile(path, marker, 0644); err != nil {
				t.Fatal(err)
			}
			f, err := os.OpenFile(path, os.O_RDWR, 0)
			if err != nil {
				t.Fatal(err)
			}
			if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
				t.Fatal(err)
			}
			fd, err := syscall.Dup(int(f.Fd()))
			if err != nil {
				t.Fatal(err)
			}
			if err := f.Close(); err != nil {
				t.Fatal(err)
			}
			t.Setenv("STATBUS_UPGRADE_MUTEX_FD", "")
			t.Setenv("STATBUS_UPGRADE_MUTEX_TOKEN", "")
			t.Setenv("STATBUS_INSTALL_MUTEX_FD", "")
			t.Setenv("STATBUS_INSTALL_MUTEX_TOKEN", "")
			t.Setenv("STATBUS_UPGRADE_MUTEX_FD", strconv.Itoa(fd))
			if scenario == "input-refusal" {
				t.Setenv(installinput.EnvConfig, filepath.Join(t.TempDir(), "missing-answers.env"))
			}
			steps := 0
			runInstallStepTableTestHook = func() error {
				steps++
				contender, err := os.OpenFile(path, os.O_RDWR, 0)
				if err != nil {
					t.Fatal(err)
				}
				defer func() { _ = contender.Close() }()
				if err := syscall.Flock(int(contender.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
					t.Fatal("contender acquired marker during first step")
				}
				got, err := os.ReadFile(path)
				if err != nil || string(got) != string(marker) {
					t.Fatalf("marker changed before first step: %s, %v", got, err)
				}
				if failStep {
					return stepError
				}
				return nil
			}
			err = runInstall()
			if earlyRefusal {
				if steps != 0 || err == nil {
					t.Fatalf("early refusal entered continuation: steps=%d err=%v", steps, err)
				}
				got, readErr := os.ReadFile(path)
				if readErr != nil || string(got) != string(marker) {
					t.Fatalf("early refusal changed marker: %s, %v", got, readErr)
				}
				contender, openErr := os.OpenFile(path, os.O_RDWR, 0)
				if openErr != nil {
					t.Fatal(openErr)
				}
				defer func() { _ = contender.Close() }()
				if lockErr := syscall.Flock(int(contender.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); lockErr != nil {
					t.Fatalf("early return leaked hold: %v", lockErr)
				}
				return
			}
			if steps != 1 || (failStep && !errors.Is(err, stepError)) || (!failStep && err != nil) {
				t.Fatalf("interrupted first install must reach step table, steps=%d err=%v", steps, err)
			}
			if _, err := os.Stat(path); !os.IsNotExist(err) {
				t.Fatalf("install continuation left stale marker: %v", err)
			}
		})
	}
}
