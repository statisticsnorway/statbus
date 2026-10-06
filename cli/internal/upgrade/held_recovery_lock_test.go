package upgrade

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestAdoptedLockRunsRealPostSwapRecoveryRoute(t *testing.T) {
	classified := UpgradeFlag{
		ID:             0,
		CommitSHA:      strings.Repeat("4", 40),
		CommitTags:     []string{"v2026.10.0-rc.15"},
		Holder:         HolderService,
		Phase:          PhaseNewSbSwapped,
		HandoffToken:   "handoff-route-450",
		Step:           "previous-death-step",
		PriorDeathStep: "guard-rolled-step",
	}
	dir, lock := heldRecoveryFixture(t, classified)
	d := &Service{
		projDir:                          dir,
		rollbackFinishPendingForTest:     func(context.Context, int) (bool, error) { return false, nil },
		servingTreeObligationForTest:     func(context.Context, int) (bool, string, error) { return false, "", nil },
		upgradeParkedReasonForTest:       func(context.Context, int) (bool, string, error) { return false, "", nil },
		incrementRecoveryAttemptsForTest: func(context.Context, int) (int, error) { return 1, nil },
		resumeNewSbSkipExternalForTest:   true,
	}
	d.AdoptFlagLock(lock)
	ctx := context.Background()
	if skip := d.RecoveryBudgetGuard(ctx); skip {
		t.Fatal("RecoveryBudgetGuard unexpectedly skipped the post-swap continuation")
	}
	guardCounted := d.recoveryPassCounted
	guardAttempts := d.recoveryPassAttempts
	guardKeptLock := d.flagLock == lock && lock.file != nil

	var advanced UpgradeFlag
	d.resumeNewSbPhaseAdvancedForTest = func(flag UpgradeFlag) error {
		advanced = flag
		onDisk, err := ReadFlagFile(dir)
		if err != nil {
			return err
		}
		if onDisk == nil || onDisk.Phase != PhaseNewSbUpgrading {
			t.Fatalf("resumeNewSb phase mutation = %#v, want %q", onDisk, PhaseNewSbUpgrading)
		}
		if onDisk.HandoffToken != classified.HandoffToken {
			t.Fatalf("resumeNewSb lost adopted handoff token: got %q want %q", onDisk.HandoffToken, classified.HandoffToken)
		}
		if _, _, err := acquireRecoveryFlock(dir, *onDisk); err == nil || !strings.Contains(err.Error(), "orchestrated upgrade is in progress") {
			t.Fatalf("real adopted flock was not retained through phase mutation: %v", err)
		}
		return nil
	}

	if err := d.recoverFromFlag(ctx); err != nil {
		t.Fatalf("real post-swap recovery route contended with its adopted lock: %v", err)
	}
	if !guardCounted || guardAttempts != 1 {
		t.Fatalf("RecoveryBudgetGuard count = counted=%v attempts=%d, want true/1", guardCounted, guardAttempts)
	}
	if !guardKeptLock {
		t.Fatal("RecoveryBudgetGuard released or replaced the adopted lock")
	}
	if advanced.Phase != PhaseNewSbUpgrading || advanced.PriorDeathStep != classified.Step {
		t.Fatalf("advanced marker = %#v, want new-sb-upgrading with RecoveryBudgetGuard-rolled history %q", advanced, classified.Step)
	}
	if d.recoveryPassAttempts != 1 {
		t.Fatalf("recovery pass attempts = %d, want guard-counted pass retained", d.recoveryPassAttempts)
	}
	if d.flagLock != nil {
		t.Fatal("terminal cleanup retained adopted lock")
	}
	if _, err := os.Stat(flagFilePath(dir)); !os.IsNotExist(err) {
		t.Fatalf("terminal cleanup left canonical marker: %v", err)
	}
}

func heldRecoveryFixture(t *testing.T, flag UpgradeFlag) (string, *FlagLock) {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o755); err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(flag)
	if err != nil {
		t.Fatal(err)
	}
	path := flagFilePath(dir)
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = file.Close()
		t.Fatal(err)
	}
	lock := &FlagLock{file: file, markerPath: path}
	t.Cleanup(lock.Close)
	return dir, lock
}

func TestRecoveryRoutingReusesAdoptedServiceLock(t *testing.T) {
	classified := UpgradeFlag{ID: 450, Holder: HolderService, Phase: PhaseNewSbSwapped, HandoffToken: "handoff-450"}
	dir, lock := heldRecoveryFixture(t, classified)
	d := &Service{projDir: dir, flagLock: lock}

	routed, held, acquired, err := d.recoveryFlock(classified)
	if err != nil {
		t.Fatalf("routing acquire contended with its adopted lock: %v", err)
	}
	if routed != lock || acquired {
		t.Fatalf("routing lock = %p acquired=%v, want adopted lock %p without a new open description", routed, acquired, lock)
	}
	if held.ID != classified.ID || held.Holder != classified.Holder || held.Phase != classified.Phase {
		t.Fatalf("held marker = %#v, want classified identity %#v", held, classified)
	}
}

func TestRecoveryRoutingWithoutHeldLockStillRefusesRealContention(t *testing.T) {
	classified := UpgradeFlag{ID: 451, Holder: HolderService, Phase: PhaseNewSbSwapped}
	dir, _ := heldRecoveryFixture(t, classified)
	d := &Service{projDir: dir}

	lock, _, _, err := d.recoveryFlock(classified)
	if err == nil || lock != nil {
		t.Fatalf("lock-less routing acquired a marker held through another open description: lock=%v err=%v", lock, err)
	}
	if !strings.Contains(err.Error(), "orchestrated upgrade is in progress") {
		t.Fatalf("contention error = %q, want existing live-holder refusal", err)
	}
}

func TestHeldRecoveryLockRevalidationRefusesMarkerDrift(t *testing.T) {
	actual := UpgradeFlag{ID: 452, Holder: HolderService, Phase: PhaseNewSbSwapped}
	tests := []struct {
		name       string
		classified UpgradeFlag
	}{
		{name: "id", classified: UpgradeFlag{ID: 999, Holder: actual.Holder, Phase: actual.Phase}},
		{name: "holder", classified: UpgradeFlag{ID: actual.ID, Holder: HolderInstall, Phase: actual.Phase}},
		{name: "phase", classified: UpgradeFlag{ID: actual.ID, Holder: actual.Holder, Phase: PhaseNewSbUpgrading}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			dir, lock := heldRecoveryFixture(t, actual)
			d := &Service{projDir: dir, flagLock: lock}
			if routed, _, _, err := d.recoveryFlock(tc.classified); err == nil || routed != nil || !strings.Contains(err.Error(), "changed after classification") {
				t.Fatalf("drift revalidation = lock=%v err=%v, want strict refusal", routed, err)
			}
		})
	}
}

func TestHeldRecoveryLockRevalidationRefusesReplacedCanonicalInode(t *testing.T) {
	classified := UpgradeFlag{ID: 453, Holder: HolderService, Phase: PhaseNewSbSwapped}
	dir, lock := heldRecoveryFixture(t, classified)
	path := flagFilePath(dir)
	replacement := path + ".replacement"
	data, err := json.Marshal(classified)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(replacement, data, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(replacement, path); err != nil {
		t.Fatal(err)
	}

	d := &Service{projDir: dir, flagLock: lock}
	if routed, _, _, err := d.recoveryFlock(classified); err == nil || routed != nil || !strings.Contains(err.Error(), "changed inode") {
		t.Fatalf("replaced inode revalidation = lock=%v err=%v, want strict refusal", routed, err)
	}
}

func TestRecoveryBudgetGuardHoldReusesAndRetainsAdoptedLock(t *testing.T) {
	classified := UpgradeFlag{ID: 454, Holder: HolderService, Phase: PhaseNewSbSwapped}
	dir, lock := heldRecoveryFixture(t, classified)
	d := &Service{projDir: dir, flagLock: lock}

	held, release, err := d.recoveryBudgetFlagHold(classified)
	if err != nil {
		t.Fatalf("budget guard hold contended with its adopted lock: %v", err)
	}
	if held.ID != classified.ID || held.Holder != classified.Holder || held.Phase != classified.Phase {
		t.Fatalf("budget guard held marker = %#v, want %#v", held, classified)
	}
	release()
	if d.flagLock != lock || lock.file == nil {
		t.Fatal("budget guard release closed or detached the inherited lock")
	}
	if _, _, acquired, err := d.recoveryFlock(classified); err != nil || acquired {
		t.Fatalf("inherited lock was not reusable after budget counting boundary: acquired=%v err=%v", acquired, err)
	}
}

func TestLegacyEmptyHolderUsesHeldPostSwapRecovery(t *testing.T) {
	dir, lock := heldRecoveryFixture(t, UpgradeFlag{ID: 0, CommitSHA: strings.Repeat("4", 40), Phase: PhaseNewSbSwapped})
	d := &Service{
		projDir: dir, flagLock: lock,
		rollbackFinishPendingForTest:     func(context.Context, int) (bool, error) { return false, nil },
		servingTreeObligationForTest:     func(context.Context, int) (bool, string, error) { return false, "", nil },
		incrementRecoveryAttemptsForTest: func(context.Context, int) (int, error) { return 1, nil },
		resumeNewSbSkipExternalForTest:   true,
	}
	advanced := false
	d.resumeNewSbPhaseAdvancedForTest = func(flag UpgradeFlag) error {
		advanced = true
		if flag.Phase != PhaseNewSbUpgrading || !IsFlockHeld(dir) {
			t.Fatal("legacy service continuation lost held lock")
		}
		return nil
	}
	if err := d.recoverFromFlag(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !advanced {
		t.Fatal("empty holder did not use existing service interpretation")
	}
}

func TestInheritedInstallRecoveryConsumesOnlyNonRestartMarker(t *testing.T) {
	for _, trigger := range []string{"install", "restart"} {
		t.Run(trigger, func(t *testing.T) {
			dir, lock := heldRecoveryFixture(t, UpgradeFlag{Holder: HolderInstall, Trigger: trigger})
			before, err := os.ReadFile(flagFilePath(dir))
			if err != nil {
				t.Fatal(err)
			}
			d := &Service{projDir: dir, flagLock: lock}
			if err := d.recoverFromFlag(context.Background()); err != nil {
				t.Fatal(err)
			}
			after, err := os.ReadFile(flagFilePath(dir))
			if trigger == "restart" {
				if err != nil || string(after) != string(before) || !IsFlockHeld(dir) {
					t.Fatal("generic recovery consumed held restart intent")
				}
			} else if !os.IsNotExist(err) {
				t.Fatalf("stale install suppressed instead of cleaned: %v", err)
			}
		})
	}
}
