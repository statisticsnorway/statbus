package upgrade

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestRestartMarkerSurvivesDaemonRecovery(t *testing.T) {
	for _, live := range []bool{true, false} {
		dir := t.TempDir()
		lock, _, err := AcquireRestartFlag(dir, "all")
		if err != nil {
			t.Fatal(err)
		}
		if err := PrepareRestart(lock, RestartIntent{Profile: "all", Unit: "unit", Daemon: true}); err != nil {
			t.Fatal(err)
		}
		before, err := os.ReadFile(flagFilePath(dir))
		if err != nil {
			t.Fatal(err)
		}
		if live {
			defer lock.Close()
		} else {
			lock.Close()
		}
		// No DB connection: restart provenance must short-circuit before DB work.
		d := &Service{projDir: dir}
		if err := d.recoverFromFlag(context.Background()); err != nil {
			t.Fatal(err)
		}
		after, err := os.ReadFile(flagFilePath(dir))
		if err != nil || string(before) != string(after) {
			t.Fatalf("restart marker altered: %v", err)
		}
		if live && !IsFlockHeld(dir) {
			t.Fatal("daemon removed live mutex")
		}
	}
}

func TestRestartRefusesMissingPayload(t *testing.T) {
	dir := t.TempDir()
	lock, err := acquireFreshFlock(dir, UpgradeFlag{Holder: HolderInstall, Trigger: "restart"})
	if err != nil {
		t.Fatal(err)
	}
	lock.Close()
	if retry, _, err := AcquireRestartFlag(dir, "all"); err == nil {
		retry.Close()
		t.Fatal("missing payload accepted")
	}
}

func TestRestartRetryContentionAcrossProcesses(t *testing.T) {
	if dir := os.Getenv("STATBUS_TEST_RESTART_CHILD"); dir != "" {
		if lock, _, err := AcquireRestartFlag(dir, "all"); err == nil {
			lock.Close()
			t.Fatal("child acquired parent restart lock")
		}
		return
	}
	dir := t.TempDir()
	lock, _, err := AcquireRestartFlag(dir, "all")
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	if err := PrepareRestart(lock, RestartIntent{Profile: "all", Daemon: false}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestRestartRetryContentionAcrossProcesses$")
	cmd.Env = append(os.Environ(), "STATBUS_TEST_RESTART_CHILD="+dir)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("child: %v %s", err, out)
	}
	if !IsFlockHeld(dir) {
		t.Fatal("child disturbed parent mutex")
	}
}

func TestFreshCreatorMustNotUnlinkWinningContender(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	path := flagFilePath(dir)
	creator, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	// The daemon opens the newly created inode and wins its flock before the
	// creator reaches flock. Separate descriptors have independent kernel locks.
	rival, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = rival.Close() })
	if err := syscall.Flock(int(rival.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}
	metadata := []byte(`{"holder":"service","id":42}`)
	if _, err := rival.Write(metadata); err != nil {
		t.Fatal(err)
	}
	if lock, err := finishFreshFlock(creator, []byte(`{"holder":"install"}`)); err == nil {
		lock.Close()
		t.Fatal("creator won rival's lock")
	}
	got, err := os.ReadFile(path)
	if err != nil || string(got) != string(metadata) {
		t.Fatalf("rival's marker lost: %q %v", got, err)
	}
	if !IsFlockHeld(dir) {
		t.Fatal("rival's mutex disappeared")
	}
	third, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = third.Close() })
	if err := syscall.Flock(int(third.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
		t.Fatal("third actor acquired replacement mutex")
	}
}
