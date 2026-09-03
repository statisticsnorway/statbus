package upgrade

import (
	"os"
	"strings"
	"testing"
)

func TestAcquireRecoveryFlock_MissingMarkerDoesNotCreate(t *testing.T) {
	dir := t.TempDir()
	classified := UpgradeFlag{ID: 41, Phase: PhaseNewSbUpgrading}

	lock, err := acquireRecoveryFlock(dir, classified)
	if err == nil || lock != nil {
		t.Fatalf("missing marker acquire = (%v, %v), want loud refusal", lock, err)
	}
	if !strings.Contains(err.Error(), "someone already finished this recovery") {
		t.Fatalf("missing marker error = %q, want finished-recovery refusal", err)
	}
	if _, statErr := os.Stat(flagFilePath(dir)); !os.IsNotExist(statErr) {
		t.Fatalf("recovery acquire created the missing marker: %v", statErr)
	}
}

func TestAcquireRecoveryFlock_ReauthorizesIDAndPhaseFromHeldDescriptor(t *testing.T) {
	dir := t.TempDir()
	actual := UpgradeFlag{
		ID:        42,
		CommitSHA: "4200000000000000000000000000000000000000",
		Holder:    HolderService,
		Phase:     PhaseNewSbUpgrading,
	}
	fresh, err := acquireFlock(dir, actual)
	if err != nil {
		t.Fatal(err)
	}
	fresh.Close()

	for _, tc := range []struct {
		name       string
		classified UpgradeFlag
	}{
		{name: "id changed", classified: UpgradeFlag{ID: actual.ID + 1, Phase: actual.Phase}},
		{name: "phase changed", classified: UpgradeFlag{ID: actual.ID, Phase: PhaseNewSbSwapped}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			lock, err := acquireRecoveryFlock(dir, tc.classified)
			if err == nil || lock != nil {
				t.Fatalf("mismatched marker acquire = (%v, %v), want refusal", lock, err)
			}
			if !strings.Contains(err.Error(), "held marker is upgrade 42 phase \"new-sb-upgrading\"") {
				t.Fatalf("mismatch error does not report held durable state: %v", err)
			}
			held, readErr := ReadFlagFile(dir)
			if readErr != nil || held == nil {
				t.Fatalf("read marker after refusal: flag=%v err=%v", held, readErr)
			}
			if held.ID != actual.ID || held.Phase != actual.Phase {
				t.Fatalf("refusal rewrote marker to id=%d phase=%q", held.ID, held.Phase)
			}
		})
	}

	lock, err := acquireRecoveryFlock(dir, actual)
	if err != nil {
		t.Fatalf("matching durable marker refused: %v", err)
	}
	lock.Close()
}
