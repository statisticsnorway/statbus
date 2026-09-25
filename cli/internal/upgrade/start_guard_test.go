package upgrade

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"
)

func TestOperatorStartGuardNamesEveryLiveInstallHeldKind(t *testing.T) {
	for _, trigger := range []string{"install", "restart", "start", "install-cli", "recovery"} {
		t.Run(trigger, func(t *testing.T) {
			dir := t.TempDir()
			started := time.Date(2026, 9, 25, 8, 0, 0, 0, time.UTC)
			owner, err := acquireFreshFlock(dir, UpgradeFlag{Holder: HolderInstall, Trigger: trigger, StartedAt: started, PID: os.Getpid()})
			if err != nil {
				t.Fatal(err)
			}
			defer owner.Close()
			guard, err := AcquireOperatorStartGuard(dir, "test:start")
			if guard != nil {
				_ = guard.Release()
				t.Fatal("operator start acquired live marker")
			}
			want := fmt.Sprintf("an installation started at 2026-09-25T08:00:00Z (process %d) is still running", os.Getpid())
			if err == nil || !strings.Contains(err.Error(), want) {
				t.Fatalf("%s live refusal = %v, want %q", trigger, err, want)
			}
		})
	}
}

func TestOperatorStartGuardRefusesLiveRecoveryLock(t *testing.T) {
	dir := t.TempDir()
	owner, err := acquireFreshFlock(dir, UpgradeFlag{ID: 17, Holder: HolderService, Trigger: "recovery", Phase: PhaseNewSbSwapped})
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = os.Remove(flagFilePath(dir))
		owner.Close()
	}()

	guard, err := AcquireOperatorStartGuard(dir, "test:start")
	if guard != nil {
		_ = guard.Release()
		t.Fatal("operator start acquired the live recovery flock")
	}
	if err == nil || !strings.Contains(err.Error(), "./sb install") {
		t.Fatalf("live recovery refusal = %v, want ./sb install guidance", err)
	}
}

func TestOperatorStartGuardAllowsAndPreservesFreeRecoveryMarker(t *testing.T) {
	dir := t.TempDir()
	want := UpgradeFlag{ID: 23, Holder: HolderService, Trigger: "recovery", Phase: PhaseNewSbSwapped, CommitSHA: strings.Repeat("a", 40)}
	owner, err := acquireFreshFlock(dir, want)
	if err != nil {
		t.Fatal(err)
	}
	owner.Close()

	before, err := os.ReadFile(flagFilePath(dir))
	if err != nil {
		t.Fatal(err)
	}
	guard, err := AcquireOperatorStartGuard(dir, "test:start")
	if err != nil {
		t.Fatalf("free parked/crashed marker blocked ordinary start: %v", err)
	}
	if !IsFlockHeld(dir) {
		t.Fatal("operator start guard did not serialize on the free recovery marker")
	}
	if err := guard.Release(); err != nil {
		t.Fatal(err)
	}
	after, err := os.ReadFile(flagFilePath(dir))
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatalf("free recovery marker was rewritten\nbefore: %s\nafter: %s", before, after)
	}
}

func TestOperatorStartGuardClosesAbsentPathRaceAndCleansUp(t *testing.T) {
	dir := t.TempDir()
	guard, err := AcquireOperatorStartGuard(dir, "test:start")
	if err != nil {
		t.Fatal(err)
	}
	if !IsFlockHeld(dir) {
		t.Fatal("transient operator start marker is not flock-held")
	}
	flag, err := ReadFlagFile(dir)
	if err != nil || flag == nil || flag.Holder != HolderInstall || flag.StartedAt.IsZero() || flag.PID != os.Getpid() {
		t.Fatalf("transient start marker lacks owner identity: flag=%+v err=%v", flag, err)
	}
	if err := guard.Release(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(flagFilePath(dir)); !os.IsNotExist(err) {
		t.Fatalf("transient operator start marker remains after release: %v", err)
	}
}
