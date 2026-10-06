package cmd

import (
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/installinput"
)

// Reviewer-only concrete interrupted first-install regression, never services/DB.
func TestReview447ExistingInstallBeforeConfig(t *testing.T) {
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
	if os.Getenv("REVIEW447_BASELINE_MODE") == "1" {
		// Shipped shell closes its non-owned marker before invoking Go.
		if err := syscall.Close(fd); err != nil {
			t.Fatal(err)
		}
	} else {
		t.Setenv("STATBUS_UPGRADE_MUTEX_FD", strconv.Itoa(fd))
	}
	steps := 0
	runInstallStepTableTestHook = func() error { steps++; return nil }
	err = runInstall()
	if steps != 1 || err != nil {
		t.Fatalf("interrupted first install must reach step table, steps=%d err=%v", steps, err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("successful install retry left stale marker: %v", err)
	}
}
