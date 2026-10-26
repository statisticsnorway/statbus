package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
)

// TestHandoffToRenamedUpgraderUnit_OrderingAndLock pins the self-upgrade unit
// handover (STATBUS-527, owner direction): it runs ONLY while this process
// holds the upgrade lock, writes+enables the new unit first, starts it before
// the old one is touched, retires the old one, and stops its own unit last —
// after the lock is released (so the new unit's bounded boot-wait can never
// exit 76 against a lock held through the stop).
func TestHandoffToRenamedUpgraderUnit_OrderingAndLock(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o755); err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("USER", "test")

	origPlatform, origCtl, origStep := upgraderHandoffPlatform, upgraderHandoffSystemctl, runUpgraderHandoffStep
	t.Cleanup(func() {
		upgraderHandoffPlatform, upgraderHandoffSystemctl, runUpgraderHandoffStep = origPlatform, origCtl, origStep
	})
	upgraderHandoffPlatform = "linux"

	var events []string
	upgraderHandoffSystemctl = func(args ...string) (string, error) {
		joined := strings.Join(args, " ")
		switch {
		case strings.HasPrefix(joined, "show "):
			return strconv.Itoa(os.Getpid()) + "\n", nil
		default:
			events = append(events, "systemctl "+joined+" lockHeld="+strconv.FormatBool(IsFlockHeld(dir)))
			return "", nil
		}
	}
	runUpgraderHandoffStep = func(projDir string, env []string, args ...string) error {
		if projDir != dir {
			t.Errorf("handoff step ran in %q, want %q", projDir, dir)
		}
		if !IsFlockHeld(projDir) {
			t.Errorf("handoff step %v ran WITHOUT the upgrade lock held", args)
		}
		found := false
		for _, e := range env {
			if e == "STATBUS_POST_UPGRADE_FIXUP=1" {
				found = true
			}
		}
		if !found {
			t.Errorf("handoff step %v lacks the fixup env signature", args)
		}
		events = append(events, "sb upgrader "+strings.Join(args, " "))
		return nil
	}

	d := NewService(dir, false, "dev", "unknown")
	d.SetLegacyUnitInstance("statbus-upgrade@test.service")
	d.handoffToRenamedUpgraderUnit()

	want := []string{
		"sb upgrader install",
		"sb upgrader start --no-block",
		"sb upgrader retire-legacy-unit",
		"systemctl --no-block stop statbus-upgrade@test.service lockHeld=false",
	}
	if len(events) != len(want) {
		t.Fatalf("handoff events = %v, want %v", events, want)
	}
	for i := range want {
		if events[i] != want[i] {
			t.Fatalf("handoff event %d = %q, want %q (all: %v)", i, events[i], want[i], events)
		}
	}
	if IsFlockHeld(dir) {
		t.Error("the upgrade lock must be released when the handoff returns")
	}
	if flag, _ := ReadFlagFile(dir); flag != nil {
		t.Errorf("the handover's marker must be removed afterwards, got %+v", flag)
	}
	// Sanity: the handoff named the new unit as target.
	if unitfloor.InstanceName("test") != "statbus-upgrader@test.service" {
		t.Fatal("unitfloor.InstanceName drifted from the new unit name")
	}
}

// TestHandoffToRenamedUpgraderUnit_RefusesBesideALiveUpgrade: with the upgrade
// lock held by another holder, the handover defers without touching anything —
// a stop beside an in-flight upgrade would interrupt it and trigger a
// rollback.
func TestHandoffToRenamedUpgraderUnit_RefusesBesideALiveUpgrade(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", t.TempDir())
	t.Setenv("USER", "test")

	origPlatform, origCtl, origStep := upgraderHandoffPlatform, upgraderHandoffSystemctl, runUpgraderHandoffStep
	t.Cleanup(func() {
		upgraderHandoffPlatform, upgraderHandoffSystemctl, runUpgraderHandoffStep = origPlatform, origCtl, origStep
	})
	upgraderHandoffPlatform = "linux"

	called := false
	upgraderHandoffSystemctl = func(args ...string) (string, error) {
		if strings.HasPrefix(strings.Join(args, " "), "show ") {
			return strconv.Itoa(os.Getpid()) + "\n", nil
		}
		called = true
		return "", nil
	}
	runUpgraderHandoffStep = func(projDir string, env []string, args ...string) error {
		called = true
		return fmt.Errorf("must not be called")
	}

	holder, err := AcquireInstallFlag(dir, "upgrade-in-flight")
	if err != nil {
		t.Fatal(err)
	}
	defer ReleaseInstallFlag(holder)

	d := NewService(dir, false, "dev", "unknown")
	d.SetLegacyUnitInstance("statbus-upgrade@test.service")
	d.handoffToRenamedUpgraderUnit()
	if called {
		t.Error("the handover must defer while the upgrade lock is held — no step, no stop")
	}
}

// TestHandoffToRenamedUpgraderUnit_OnlyFromTheLegacyUnitsOwnProcess: a Service
// whose process is NOT the legacy unit's main PID (every one-shot verb) never
// hands off.
func TestHandoffToRenamedUpgraderUnit_OnlyFromTheLegacyUnitsOwnProcess(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())
	t.Setenv("USER", "test")

	origPlatform, origCtl, origStep := upgraderHandoffPlatform, upgraderHandoffSystemctl, runUpgraderHandoffStep
	t.Cleanup(func() {
		upgraderHandoffPlatform, upgraderHandoffSystemctl, runUpgraderHandoffStep = origPlatform, origCtl, origStep
	})
	upgraderHandoffPlatform = "linux"

	called := false
	upgraderHandoffSystemctl = func(args ...string) (string, error) {
		if strings.HasPrefix(strings.Join(args, " "), "show ") {
			return "999999\n", nil // someone else's PID
		}
		called = true
		return "", nil
	}
	runUpgraderHandoffStep = func(projDir string, env []string, args ...string) error {
		called = true
		return fmt.Errorf("must not be called")
	}

	d := NewService(dir, false, "dev", "unknown")
	d.SetLegacyUnitInstance("statbus-upgrade@test.service")
	d.handoffToRenamedUpgraderUnit()
	if called {
		t.Error("a process that is not the legacy unit's main PID must not hand off")
	}
	if IsFlockHeld(dir) {
		t.Error("no lock may be taken when the handoff does not run")
	}
}
