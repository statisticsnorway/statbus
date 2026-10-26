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

// seedCrashedServiceMarker writes a service-holder upgrade marker with a FREE
// flock: the on-disk state of a crashed upgrade (between restarts or in a
// StartLimitBurst stop) or a deliberately parked one. Returns its exact bytes.
func seedCrashedServiceMarker(t *testing.T, dir, phase string) []byte {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o755); err != nil {
		t.Fatal(err)
	}
	marker := `{
  "id": 17,
  "commit_sha": "0123456789abcdef0123456789abcdef01234567",
  "started_at": "2026-10-26T12:00:00Z",
  "invoked_by": "scheduled",
  "trigger": "scheduled",
  "holder": "service",
  "phase": "` + phase + `",
  "backup_path": "/home/test/statbus/statbus-backups/pre-upgrade-20261026"
}`
	if err := os.WriteFile(flagFilePath(dir), []byte(marker), 0o644); err != nil {
		t.Fatal(err)
	}
	return []byte(marker)
}

// TestHandoffToRenamedUpgraderUnit_PreservesRecoveryMarker (B1): with a
// crashed or parked upgrade's marker on disk (flock free), the handover
// defers and the marker survives byte-identically. Before the fix the handoff
// adopted the marker via AcquireInstallFlag and ReleaseInstallFlag deleted
// it, erasing the recovery path.
func TestHandoffToRenamedUpgraderUnit_PreservesRecoveryMarker(t *testing.T) {
	for _, phase := range []string{PhaseNewSbSwapped, PhaseNewSbUpgrading} {
		t.Run("phase="+phase, func(t *testing.T) {
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
					return strconv.Itoa(os.Getpid()) + "\n", nil
				}
				called = true
				return "", nil
			}
			runUpgraderHandoffStep = func(projDir string, env []string, args ...string) error {
				called = true
				return fmt.Errorf("must not be called")
			}

			marker := seedCrashedServiceMarker(t, dir, phase)

			d := NewService(dir, false, "dev", "unknown")
			d.SetLegacyUnitInstance("statbus-upgrade@test.service")
			if d.handoffToRenamedUpgraderUnit() {
				t.Error("the handover must defer while a crashed/parked marker exists")
			}
			if called {
				t.Error("a deferred handover runs no step and no stop")
			}
			got, err := os.ReadFile(flagFilePath(dir))
			if err != nil {
				t.Fatalf("the recovery marker must still exist: %v", err)
			}
			if string(got) != string(marker) {
				t.Fatalf("the recovery marker was rewritten:\n got: %s\nwant: %s", got, marker)
			}
			if IsFlockHeld(dir) {
				t.Error("the deferred handover must not hold the lock")
			}
		})
	}
}

// TestHandoffToRenamedUpgraderUnit_HandedOffStopsRun (B2): after the self-stop
// is submitted, the handoff reports handedOff and is a no-op on a second call,
// and Run's source exits on d.handedOff BEFORE it can reach the listen loop or
// executeScheduled — a claimed upgrade there would be SIGTERMed mid-flight by
// the queued stop.
func TestHandoffToRenamedUpgraderUnit_HandedOffStopsRun(t *testing.T) {
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

	var stops int
	upgraderHandoffSystemctl = func(args ...string) (string, error) {
		joined := strings.Join(args, " ")
		if strings.HasPrefix(joined, "show ") {
			return strconv.Itoa(os.Getpid()) + "\n", nil
		}
		if strings.HasPrefix(joined, "--no-block stop ") {
			stops++
		}
		return "", nil
	}
	runUpgraderHandoffStep = func(projDir string, env []string, args ...string) error {
		return nil
	}

	d := NewService(dir, false, "dev", "unknown")
	d.SetLegacyUnitInstance("statbus-upgrade@test.service")
	if !d.handoffToRenamedUpgraderUnit() {
		t.Fatal("a complete handover must report handedOff")
	}
	if !d.handedOff {
		t.Fatal("d.handedOff must be set once the self-stop is submitted")
	}
	if stops != 1 {
		t.Fatalf("expected exactly one self-stop, got %d", stops)
	}
	// A second call (the boot-time net after the end-of-upgrade handoff) is a
	// no-op: no second stop, no re-acquisition.
	if !d.handoffToRenamedUpgraderUnit() {
		t.Fatal("a repeated handoff must keep reporting handedOff")
	}
	if stops != 1 {
		t.Fatalf("a repeated handoff must not stop again, got %d stops", stops)
	}

	// Run's contract: the handedOff guard sits between the handoff call and
	// the main loop, so no claim can follow a submitted self-stop.
	src, err := os.ReadFile("service.go")
	if err != nil {
		t.Fatal(err)
	}
	runBody := funcBodyOf(t, string(src), "func (d *Service) Run(")
	handoffIdx := strings.Index(runBody, "d.handoffToRenamedUpgraderUnit()")
	guardIdx := strings.Index(runBody, "if d.handedOff {")
	listenIdx := strings.Index(runBody, "d.startListenLoop(")
	claimIdx := strings.Index(runBody, "executeScheduled")
	if handoffIdx < 0 || guardIdx < 0 || listenIdx < 0 || claimIdx < 0 {
		t.Fatalf("Run must call the handoff, guard on handedOff, and contain the listen loop and claim path")
	}
	if handoffIdx >= guardIdx || guardIdx >= listenIdx || guardIdx >= claimIdx {
		t.Fatalf("Run's handedOff guard must sit between the handoff and the listen loop/claim path (handoff=%d guard=%d listen=%d claim=%d)",
			handoffIdx, guardIdx, listenIdx, claimIdx)
	}
	guardReturn := strings.Index(runBody[guardIdx:], "return nil")
	if guardReturn < 0 || guardIdx+guardReturn > listenIdx {
		t.Fatal("the handedOff guard must return before the listen loop")
	}
}

// funcBodyOf extracts a top-level func's body (brace-balanced) for contract
// assertions.
func funcBodyOf(t *testing.T, src, signature string) string {
	t.Helper()
	idx := strings.Index(src, signature)
	if idx < 0 {
		t.Fatalf("signature %q not found", signature)
	}
	open := strings.Index(src[idx:], "{")
	if open < 0 {
		t.Fatalf("signature %q has no body", signature)
	}
	start := idx + open
	depth := 0
	for i := start; i < len(src); i++ {
		switch src[i] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return src[start : i+1]
			}
		}
	}
	t.Fatalf("signature %q body is unbalanced", signature)
	return ""
}
