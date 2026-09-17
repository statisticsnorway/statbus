package upgrade

import (
	"os"
	"strings"
	"testing"
)

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
	if err := guard.Release(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(flagFilePath(dir)); !os.IsNotExist(err) {
		t.Fatalf("transient operator start marker remains after release: %v", err)
	}
}
