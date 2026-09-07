package upgrade

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRollbackAbortsBeforeDestructiveWorkWhenDirectionStampFails(t *testing.T) {
	dir := t.TempDir()
	record := filepath.Join(dir, "commands")
	bin := filepath.Join(dir, "bin")
	if err := os.Mkdir(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"docker", "git", "rsync"} {
		script := "#!/bin/sh\nprintf '%s\\n' \"$0 $*\" >> " + record + "\n"
		if err := os.WriteFile(filepath.Join(bin, name), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	seed := UpgradeFlag{ID: 354, Holder: HolderService, Phase: PhaseNewSbUpgrading, Step: StepMigrateUp}
	lock, err := acquireFlock(dir, seed)
	if err != nil {
		t.Fatal(err)
	}
	// Keep the service's nominal held-lock object but invalidate its descriptor.
	// This exercises the real mutateHeldFlag failure at the common rollback entry.
	lock.file = nil
	d := &Service{projDir: dir, flagLock: lock}

	err = d.rollback(context.Background(), seed.ID, "rc.test", "", nil, "original failure", "snapshot", nil)
	var stampErr *RollbackDirectionStampError
	if !errors.As(err, &stampErr) {
		t.Fatalf("rollback error = %T %v, want *RollbackDirectionStampError", err, err)
	}
	const want = "rollback aborted before destructive work: durably stamp StepRollback: mutate held upgrade flag: no flag file held"
	if err.Error() != want {
		t.Fatalf("abort error = %q, want %q", err, want)
	}
	if data, readErr := os.ReadFile(record); readErr == nil {
		t.Fatalf("destructive command ran after stamp failure: %s", data)
	} else if !os.IsNotExist(readErr) {
		t.Fatal(readErr)
	}
	got, readErr := ReadFlagFile(dir)
	if readErr != nil || got == nil {
		t.Fatalf("read retained marker: flag=%v err=%v", got, readErr)
	}
	if got.Step != StepMigrateUp || got.PriorDeathStep != "" {
		t.Fatalf("failed stamp changed durable history: step=%q prior=%q", got.Step, got.PriorDeathStep)
	}
}

func TestRecordRollbackCommitRollsHistoryExactlyOnce(t *testing.T) {
	dir := t.TempDir()
	seed := UpgradeFlag{ID: 354, CommitSHA: "abc123", Holder: HolderService, Phase: PhaseNewSbUpgrading, Step: StepMigrateUp, PriorDeathStep: StepConfigGenerate}
	lock, err := acquireFlock(dir, seed)
	if err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: dir, flagLock: lock}
	if err := d.recordRollbackCommit(); err != nil {
		t.Fatal(err)
	}
	d.flagLock = nil
	lock.Close()
	got, err := ReadFlagFile(dir)
	if err != nil || got == nil {
		t.Fatalf("read stamped flag: got=%v err=%v", got, err)
	}
	if got.Step != StepRollback || got.PriorDeathStep != StepMigrateUp {
		t.Fatalf("rollback history did not roll exactly once: step=%q prior=%q", got.Step, got.PriorDeathStep)
	}
}

func TestHeldRollbackStepWinsRaceOverForwardClassification(t *testing.T) {
	testHeldMarkerRaceRoute(t, StepMigrateUp, StepRollback, recoveryRouteRollback)
}

func TestStaleRollbackStepCannotAuthorizeRollbackAfterHeldStepChanges(t *testing.T) {
	testHeldMarkerRaceRoute(t, StepRollback, StepMigrateUp, recoveryRouteObservedState)
}

func testHeldMarkerRaceRoute(t *testing.T, classifiedStep, heldStep string, want recoveryRoute) {
	t.Helper()
	dir := t.TempDir()
	classified := UpgradeFlag{ID: 354, CommitSHA: strings.Repeat("a", 40), Holder: HolderService, Phase: PhaseNewSbUpgrading, Step: classifiedStep}
	owner, err := acquireFlock(dir, classified)
	if err != nil {
		t.Fatal(err)
	}
	ownerReady := make(chan struct{})
	releaseOwner := make(chan struct{})
	ownerDone := make(chan error, 1)
	go func() {
		close(ownerReady)
		<-releaseOwner
		ownerService := &Service{projDir: dir, flagLock: owner}
		if err := ownerService.mutateHeldFlag(func(flag *UpgradeFlag) { flag.Step = heldStep }); err != nil {
			ownerDone <- err
			return
		}
		owner.Close()
		ownerDone <- nil
	}()
	<-ownerReady
	close(releaseOwner)
	if err := <-ownerDone; err != nil {
		t.Fatal(err)
	}

	lock, held, err := acquireRecoveryFlock(dir, classified)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	if held.Step != heldStep {
		t.Fatalf("held step = %q, want %q", held.Step, heldStep)
	}
	// An at-target-looking ledger is intentionally irrelevant when the held
	// marker says rollback. Conversely, stale pre-lock rollback is irrelevant
	// when the held marker no longer says rollback.
	if got := routeHeldRecoveryFlag(held); got != want {
		t.Fatalf("route for classified=%q held=%q = %v, want %v", classifiedStep, heldStep, got, want)
	}
}
