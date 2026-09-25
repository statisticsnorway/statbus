package upgrade

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
)

// Real filesystem and flock APIs, no repository config or database connection.
func TestRecoverFromFlagKeepsLiveInstallMutex(t *testing.T) {
	dir := t.TempDir()
	lock, err := AcquireInstallFlag(dir, "test-first-install")
	if err != nil {
		t.Fatal(err)
	}
	defer ReleaseInstallFlag(lock)
	flag, err := ReadFlagFile(dir)
	if err != nil || flag == nil || flag.Holder != HolderInstall || flag.PID != os.Getpid() {
		t.Fatalf("install marker must record holder and diagnostic process ID: flag=%+v err=%v", flag, err)
	}
	before, err := os.Stat(flagFilePath(dir))
	if err != nil {
		t.Fatal(err)
	}
	beforeBytes, err := os.ReadFile(flagFilePath(dir))
	if err != nil {
		t.Fatal(err)
	}
	service := NewService(dir, false, "test", "test")
	recoveryErr := service.RecoverFromFlag(context.Background())
	if recoveryErr != nil {
		t.Fatalf("live install must not churn service startup: %v", recoveryErr)
	}
	after, err := os.Stat(flagFilePath(dir))
	if err != nil {
		t.Errorf("live install marker disappeared: %v", err)
	} else if !os.SameFile(before, after) {
		t.Error("live install marker inode changed")
	}
	afterBytes, err := os.ReadFile(flagFilePath(dir))
	if err != nil || string(beforeBytes) != string(afterBytes) {
		t.Errorf("live install metadata changed: err=%v before=%s after=%s", err, beforeBytes, afterBytes)
	}
	second, err := AcquireInstallFlag(dir, "test-second-install")
	if err == nil {
		ReleaseInstallFlag(second)
		t.Error("second install acquired mutex while first still holds its flock")
	} else if !strings.Contains(err.Error(), fmt.Sprintf("(process %d)", os.Getpid())) || strings.Contains(err.Error(), "lsof") {
		t.Errorf("contended install must identify holder without internal command: %v", err)
	}
}

func TestRecoverFromFlagClearsStaleInstallMutex(t *testing.T) {
	dir := t.TempDir()
	lock, err := AcquireInstallFlag(dir, "test-crashed-install")
	if err != nil {
		t.Fatal(err)
	}
	lock.Close() // model process exit: fd released, marker retained
	if err := NewService(dir, false, "test", "test").RecoverFromFlag(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(flagFilePath(dir)); !os.IsNotExist(err) {
		t.Fatalf("stale marker not removed: %v", err)
	}
	next, err := AcquireInstallFlag(dir, "test-next-install")
	if err != nil {
		t.Fatal(err)
	}
	ReleaseInstallFlag(next)
}

func TestRecoverFromFlagPreservesRestartMarkers(t *testing.T) {
	for _, live := range []bool{true, false} {
		t.Run(fmt.Sprintf("live=%v", live), func(t *testing.T) {
			dir := t.TempDir()
			lock, err := acquireFreshFlock(dir, UpgradeFlag{Holder: HolderInstall, Trigger: "restart"})
			if err != nil {
				t.Fatal(err)
			}
			defer lock.Close()
			if !live {
				lock.Close()
			}
			before, err := os.ReadFile(flagFilePath(dir))
			if err != nil {
				t.Fatal(err)
			}
			if err := NewService(dir, false, "test", "test").RecoverFromFlag(context.Background()); err != nil {
				t.Fatal(err)
			}
			after, err := os.ReadFile(flagFilePath(dir))
			if err != nil || string(after) != string(before) {
				t.Fatalf("restart marker changed: %v", err)
			}
		})
	}
}

func TestRecoveredInstallCleanupUsesHeldRestartTrigger(t *testing.T) {
	dir := t.TempDir()
	classified := UpgradeFlag{Holder: HolderInstall, Trigger: "install"}
	actual := classified
	actual.Trigger = "restart"
	initial, err := acquireFreshFlock(dir, actual)
	if err != nil {
		t.Fatal(err)
	}
	initial.Close()
	lock, held, err := acquireRecoveryFlock(dir, classified)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	removed, err := removeRecoveredInstallFlag(lock, held)
	if err != nil || removed {
		t.Fatalf("held restart cleanup removed=%v err=%v", removed, err)
	}
	flag, err := ReadFlagFile(dir)
	if err != nil || flag == nil || flag.Trigger != "restart" {
		t.Fatalf("lost restart marker: %+v %v", flag, err)
	}
}

func TestRecoveredInstallCleanupRejectsReplacedInode(t *testing.T) {
	dir := t.TempDir()
	initial, err := AcquireInstallFlag(dir, "stale")
	if err != nil {
		t.Fatal(err)
	}
	initial.Close()
	classified, err := ReadFlagFile(dir)
	if err != nil {
		t.Fatal(err)
	}
	lock, held, err := acquireRecoveryFlock(dir, *classified)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	path := flagFilePath(dir)
	if err := os.Rename(path, path+".old"); err != nil {
		t.Fatal(err)
	}
	replacement, err := AcquireInstallFlag(dir, "replacement")
	if err != nil {
		t.Fatal(err)
	}
	defer ReleaseInstallFlag(replacement)
	removed, err := removeRecoveredInstallFlag(lock, held)
	if err == nil || removed {
		t.Fatalf("replaced inode cleanup removed=%v err=%v", removed, err)
	}
	flag, err := ReadFlagFile(dir)
	if err != nil || flag == nil || flag.InvokedBy != "replacement" {
		t.Fatalf("lost replacement marker: %+v %v", flag, err)
	}
	if !IsFlockHeld(dir) {
		t.Fatal("replacement mutex no longer held")
	}
}
