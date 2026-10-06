package cmd

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func TestScheduledWithLockConfigErrorClosesOnlyDescriptor(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
	marker := []byte(`{"id":447,"holder":"service","phase":"new-sb-swapped","commit_sha":"original-target","backup_path":"/retained/backup","recreate":true,"trigger":"install-cli","handoff_token":"bridge"}`)
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
	_ = f.Close()
	t.Setenv("STATBUS_UPGRADE_MUTEX_FD", strconv.Itoa(fd))
	t.Setenv("STATBUS_UPGRADE_MUTEX_TOKEN", "bridge")
	lock, _, err := upgrade.AdoptInheritedUpgradeFlag(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	old := inlineDispatchLoadConfig
	defer func() { inlineDispatchLoadConfig = old }()
	inlineDispatchLoadConfig = func(context.Context, *upgrade.Service) error { return errors.New("scratch config refusal") }
	if err := runInlineUpgradeScheduledWithLock(dir, &install.Detail{}, lock); err == nil {
		t.Fatal("expected config refusal")
	}
	probe, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = probe.Close() }()
	err = syscall.Flock(int(probe.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	if err != nil {
		t.Fatalf("config-error leaked adopted lock: %v", err)
	}
	got, err := os.ReadFile(path)
	if err != nil || string(got) != string(marker) {
		t.Fatalf("marker changed: %s %v", got, err)
	}
}
