package upgrade

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestRestartMarkerSurvivesDaemonRecovery(t *testing.T) {
	for _, live := range []bool{true, false} {
		dir := t.TempDir()
		lock, _, _, err := AcquireRestartFlag(dir, "all")
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

func TestInterruptedAndLiveRestartClassification(t *testing.T) {
	dir := t.TempDir()
	lock, _, _, err := AcquireRestartFlag(dir, "all")
	if err != nil {
		t.Fatal(err)
	}
	assertRestartOwner := func() {
		t.Helper()
		flag, err := ReadFlagFile(dir)
		if err != nil || flag == nil || flag.StartedAt.IsZero() || flag.PID != os.Getpid() || flag.Holder != HolderInstall {
			t.Fatalf("restart marker lacks current owner identity: flag=%+v err=%v", flag, err)
		}
	}
	assertRestartOwner() // initial marker
	if err := PrepareRestart(lock, RestartIntent{Profile: "all", Prepared: true}); err != nil {
		t.Fatal(err)
	}
	assertRestartOwner() // prepared marker rewrite
	if !IsFlockHeld(dir) {
		t.Fatal("live restart lock not held")
	}
	if err := CheckRestartBarrier(dir); err == nil || !strings.Contains(err.Error(), fmt.Sprintf("(process %d)", os.Getpid())) {
		t.Fatalf("live restart barrier omits holder identity: %v", err)
	}
	if retry, _, _, err := AcquireRestartFlag(dir, "all"); err == nil {
		retry.Close()
		t.Fatal("live restart was taken over")
	} else if !strings.Contains(err.Error(), fmt.Sprintf("(process %d)", os.Getpid())) {
		t.Fatalf("live restart refusal omits holder PID: %v", err)
	}
	lock.Close()
	if IsFlockHeld(dir) {
		t.Fatal("interrupted restart lock still held")
	}
	if err := CheckRestartBarrier(dir); err == nil || strings.Contains(err.Error(), fmt.Sprintf("(process %d)", os.Getpid())) {
		t.Fatalf("stale restart barrier must not claim PID is live: %v", err)
	}
	retry, intent, _, err := AcquireRestartFlag(dir, "all")
	if err != nil || intent == nil || intent.Profile != "all" || !intent.Prepared {
		t.Fatalf("stale intent lost: %+v %v", intent, err)
	}
	retry.Close()
}

func TestRestartRefusesMissingPayload(t *testing.T) {
	dir := t.TempDir()
	lock, err := acquireFreshFlock(dir, UpgradeFlag{Holder: HolderInstall, Trigger: "restart"})
	if err != nil {
		t.Fatal(err)
	}
	lock.Close()
	if retry, _, _, err := AcquireRestartFlag(dir, "all"); err == nil {
		retry.Close()
		t.Fatal("missing payload accepted")
	}
}

func TestRestartBorrowsFreeRecoveryMarkerWithoutOverwritingIt(t *testing.T) {
	dir := t.TempDir()
	seed := UpgradeFlag{ID: 17, Holder: HolderService, Trigger: "recovery", Phase: PhaseNewSbSwapped, CommitSHA: "0123456789abcdef"}
	owner, err := acquireFreshFlock(dir, seed)
	if err != nil {
		t.Fatal(err)
	}
	owner.Close()
	before, err := os.ReadFile(flagFilePath(dir))
	if err != nil {
		t.Fatal(err)
	}

	lock, prior, preserve, err := AcquireRestartFlag(dir, "all")
	if err != nil {
		t.Fatalf("free parked marker blocked restart: %v", err)
	}
	if prior != nil || !preserve {
		t.Fatalf("restart acquisition = prior %#v preserve=%v, want borrowed recovery marker", prior, preserve)
	}
	lock.Close()
	after, err := os.ReadFile(flagFilePath(dir))
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatalf("restart overwrote borrowed recovery marker\nbefore: %s\nafter: %s", before, after)
	}
}

func TestRestartRetryContentionAcrossProcesses(t *testing.T) {
	if dir := os.Getenv("STATBUS_TEST_RESTART_CHILD"); dir != "" {
		if lock, _, _, err := AcquireRestartFlag(dir, "all"); err == nil {
			lock.Close()
			t.Fatal("child acquired parent restart lock")
		}
		return
	}
	dir := t.TempDir()
	lock, _, _, err := AcquireRestartFlag(dir, "all")
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

func TestFreshAtomicCreatorMustNotOverwriteWinningContender(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	path := flagFilePath(dir)
	metadata := []byte(`{"holder":"service","id":42}`)
	if err := os.WriteFile(path, metadata, 0o600); err != nil {
		t.Fatal(err)
	}
	rival, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = rival.Close() })
	if err := syscall.Flock(int(rival.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}
	if lock, err := acquireFreshFlock(dir, UpgradeFlag{Holder: HolderInstall}); err == nil {
		lock.Close()
		t.Fatal("fresh creator overwrote rival marker")
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
