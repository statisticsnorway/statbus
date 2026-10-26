package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// ── Recorded systemd state ─────────────────────────────────────────────────

// fakeSystemdUnit is one unit in the recorded state.
type fakeSystemdUnit struct {
	loadState   string // "loaded" or "not-found"
	activeState string // "active", "inactive", "failed", ...
	enabled     string // "enabled", "disabled", ...
	mainPID     int
	// stopPollsBeforeDead simulates a main process that takes a moment to
	// exit after `systemctl stop`: MainPID stays non-zero for this many
	// `show -p MainPID` reads after the stop.
	stopPollsBeforeDead int
	stopCalls           int
}

// fakeSystemd is the recorded systemd state the upgrader tests run against
// (AC2's "recorded systemd state"): a complete in-memory user manager driven
// through the upgraderSystemctl seam.
type fakeSystemd struct {
	units map[string]*fakeSystemdUnit
	calls [][]string
}

func newFakeSystemd() *fakeSystemd {
	return &fakeSystemd{units: map[string]*fakeSystemdUnit{}}
}

func (f *fakeSystemd) unit(name string) *fakeSystemdUnit {
	u, ok := f.units[name]
	if !ok {
		u = &fakeSystemdUnit{loadState: "not-found", activeState: "inactive", enabled: "disabled"}
		f.units[name] = u
	}
	// A unit whose template file exists on disk is "loaded" — the real
	// manager discovers it at daemon-reload; the recorded state derives it.
	if u.loadState == "not-found" && strings.HasSuffix(name, ".service") {
		base := strings.TrimSuffix(strings.SplitN(name, "@", 2)[0], "@") + "@.service"
		if strings.Contains(name, "@") {
			if _, err := os.Stat(filepath.Join(upgraderUserUnitDir(), base)); err == nil {
				u.loadState = "loaded"
			}
		}
	}
	return u
}

// run implements the upgraderSystemctl signature. Arguments arrive WITHOUT
// `--user` (the seam prepends it).
func (f *fakeSystemd) run(args ...string) (string, error) {
	f.calls = append(f.calls, append([]string{}, args...))
	// Strip global flags.
	for len(args) > 0 && strings.HasPrefix(args[0], "--") {
		args = args[1:]
	}
	if len(args) == 0 {
		return "", fmt.Errorf("no subcommand")
	}
	sub := args[0]
	rest := args[1:]
	switch sub {
	case "daemon-reload":
		return "", nil
	case "is-active":
		u := f.unit(rest[0])
		if u.activeState == "active" {
			return "active\n", nil
		}
		return u.activeState + "\n", fmt.Errorf("not active")
	case "is-enabled":
		u := f.unit(rest[0])
		if u.enabled == "enabled" {
			return "enabled\n", nil
		}
		return u.enabled + "\n", fmt.Errorf("not enabled")
	case "show":
		name := ""
		props := []string{}
		for i := 0; i < len(rest); i++ {
			switch {
			case rest[i] == "-p" && i+1 < len(rest):
				props = append(props, rest[i+1])
				i++
			case strings.HasPrefix(rest[i], "--property="):
				props = append(props, strings.TrimPrefix(rest[i], "--property="))
			case rest[i] == "--value":
			default:
				name = rest[i]
			}
		}
		u := f.unit(name)
		var b strings.Builder
		valueOnly := len(props) == 1
		for _, p := range props {
			var v string
			switch p {
			case "LoadState":
				v = u.loadState
			case "ActiveState":
				v = u.activeState
			case "MainPID":
				if u.stopCalls > 0 && u.stopPollsBeforeDead > 0 {
					u.stopPollsBeforeDead--
				}
				if u.stopCalls > 0 && u.stopPollsBeforeDead == 0 {
					u.mainPID = 0
					u.activeState = "inactive"
				}
				v = strconv.Itoa(u.mainPID)
			case "Result":
				v = "success"
				if u.activeState == "failed" {
					v = "start-limit-hit"
				}
			default:
				v = ""
			}
			if valueOnly {
				b.WriteString(v + "\n")
			} else {
				b.WriteString(p + "=" + v + "\n")
			}
		}
		return b.String(), nil
	case "enable":
		u := f.unit(rest[0])
		if u.loadState == "not-found" {
			return "", fmt.Errorf("unit %s not found", rest[0])
		}
		u.enabled = "enabled"
		return "", nil
	case "disable":
		u := f.unit(rest[0])
		u.enabled = "disabled"
		return "", nil
	case "start":
		u := f.unit(rest[0])
		if u.loadState == "not-found" {
			return "", fmt.Errorf("unit %s not found", rest[0])
		}
		u.activeState = "active"
		if u.mainPID == 0 {
			u.mainPID = 4242
		}
		return "", nil
	case "stop":
		u := f.unit(rest[0])
		if u.loadState == "not-found" {
			return "", fmt.Errorf("unit %s not loaded", rest[0])
		}
		u.stopCalls++
		if u.stopPollsBeforeDead == 0 {
			u.mainPID = 0
			u.activeState = "inactive"
		}
		return "", nil
	case "restart":
		u := f.unit(rest[0])
		if u.loadState == "not-found" {
			return "", fmt.Errorf("unit %s not found", rest[0])
		}
		u.activeState = "active"
		return "", nil
	case "reset-failed":
		u := f.unit(rest[0])
		if u.activeState == "failed" {
			u.activeState = "inactive"
		}
		return "", nil
	case "mask", "unmask", "kill":
		return "", nil
	}
	return "", fmt.Errorf("fakeSystemd: unhandled %q", strings.Join(args, " "))
}

func (f *fakeSystemd) called(sub string) bool {
	for _, c := range f.calls {
		for _, a := range c {
			if a == sub {
				return true
			}
		}
	}
	return false
}

// installFakeSystemd points the upgraderSystemctl seam at a recorded state
// and restores it at cleanup.
func installFakeSystemd(t *testing.T) *fakeSystemd {
	t.Helper()
	f := newFakeSystemd()
	orig := upgraderSystemctl
	upgraderSystemctl = f.run
	origPlatform := upgraderPlatform
	upgraderPlatform = "linux"
	t.Cleanup(func() { upgraderSystemctl = orig; upgraderPlatform = origPlatform })
	return f
}

// upgraderFixture lays out a temp HOME (unit dir) and a temp project dir with
// the ops/statbus-upgrader.service template, with USER set.
func upgraderFixture(t *testing.T, template string) (dir string) {
	t.Helper()
	t.Setenv("USER", "test")
	home := t.TempDir()
	t.Setenv("HOME", home)
	if err := os.MkdirAll(filepath.Join(home, ".config", "systemd", "user"), 0o755); err != nil {
		t.Fatal(err)
	}
	dir = t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "ops"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "ops", "statbus-upgrader.service"), []byte(template), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

const upgraderTestTemplate = "[Unit]\nDescription=StatBus Upgrader\n[Service]\nExecStart=%h/statbus/sb upgrader run\n"

// ── AC8: the hidden alias ─────────────────────────────────────────────────

// TestUpgradeServiceAliasIsUpgraderRun pins AC8: `sb upgrade service` still
// starts the upgrader, as a HIDDEN alias of `sb upgrader run` — both commands
// run the same RunE, so a pre-rename unit's ExecStart keeps working.
func TestUpgradeServiceAliasIsUpgraderRun(t *testing.T) {
	if !upgradeServiceCmd.Hidden {
		t.Error("sb upgrade service must be hidden — it exists only for pre-rename units")
	}
	alias := reflect.ValueOf(upgradeServiceCmd.RunE).Pointer()
	run := reflect.ValueOf(upgraderRunCmd.RunE).Pointer()
	shared := reflect.ValueOf(upgradeServiceRunE).Pointer()
	if alias != run || run != shared {
		t.Error("sb upgrade service and sb upgrader run must share one RunE (upgradeServiceRunE)")
	}
}

// ── AC1: stop ─────────────────────────────────────────────────────────────

// TestUpgraderStopRefusesWhileUpgradeHoldsLock: a stop never interrupts a live
// upgrade — while the upgrade lock is held, `sb upgrader stop` refuses with a
// wait message and systemd never sees a stop.
func TestUpgraderStopRefusesWhileUpgradeHoldsLock(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)
	u := f.unit("statbus-upgrader@test.service")
	u.loadState = "loaded"
	u.activeState = "active"
	u.mainPID = 4242

	// A live upgrade holds the canonical flock.
	holder, err := upgrade.AcquireInstallFlag(dir, "upgrade-in-flight")
	if err != nil {
		t.Fatal(err)
	}
	defer upgrade.ReleaseInstallFlag(holder)

	err = runUpgraderStop(dir)
	if err == nil {
		t.Fatal("stop must refuse while an upgrade holds the lock")
	}
	if !strings.Contains(err.Error(), "ait for it to finish") {
		t.Fatalf("the refusal must tell the operator to wait, got: %v", err)
	}
	if f.called("stop") {
		t.Fatal("systemd must never see a stop while an upgrade holds the lock")
	}
	if u.activeState != "active" {
		t.Fatal("the unit must still be active after a refused stop")
	}
}

// TestUpgraderStopWaitsForMainProcessExit: stop returns only after the unit's
// MainPID has exited — the fake keeps the process alive for three polls after
// `systemctl stop`, and the stop must not return before it is gone.
func TestUpgraderStopWaitsForMainProcessExit(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)
	u := f.unit("statbus-upgrader@test.service")
	u.loadState = "loaded"
	u.activeState = "active"
	u.mainPID = 4242
	u.stopPollsBeforeDead = 3

	if err := runUpgraderStop(dir); err != nil {
		t.Fatal(err)
	}
	if u.mainPID != 0 || u.activeState != "inactive" {
		t.Fatalf("stop returned before the main process exited (pid=%d state=%s)", u.mainPID, u.activeState)
	}
	// The lock is released afterwards, so a later acquirer wins.
	if upgrade.IsFlockHeld(dir) {
		t.Fatal("the upgrade lock must be released after a successful stop")
	}
}

// TestUpgraderStopFailsWhenProcessSurvives: if the main process is still there
// after `systemctl stop` returned, stop says so instead of lying.
func TestUpgraderStopFailsWhenProcessSurvives(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)
	u := f.unit("statbus-upgrader@test.service")
	u.loadState = "loaded"
	u.activeState = "active"
	u.mainPID = 4242
	u.stopPollsBeforeDead = 1 << 20 // never exits

	origTimeout, origPoll := upgraderStopVerifyTimeout, upgraderStopPollInterval
	upgraderStopVerifyTimeout, upgraderStopPollInterval = 300*time.Millisecond, 10*time.Millisecond
	t.Cleanup(func() { upgraderStopVerifyTimeout, upgraderStopPollInterval = origTimeout, origPoll })

	err := runUpgraderStop(dir)
	if err == nil || !strings.Contains(err.Error(), "still has a main process") {
		t.Fatalf("stop must report a surviving main process, got: %v", err)
	}
}

// TestUpgraderStopWithoutUnitIsANoOp: nothing installed → nothing to stop,
// and no error.
func TestUpgraderStopWithoutUnitIsANoOp(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	installFakeSystemd(t)
	if err := runUpgraderStop(dir); err != nil {
		t.Fatal(err)
	}
}

// ── AC2: migration with a recorded systemd state ──────────────────────────

// TestUpgraderInstallMigratesLegacyUnit runs the shared install against a
// recorded box state: the pre-rename unit installed, enabled and running. It
// must end with exactly one unit — statbus-upgrader@ — written byte-identical
// to the repo template and enabled, the legacy unit stopped, disabled and
// deleted.
func TestUpgraderInstallMigratesLegacyUnit(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)

	// The recorded pre-migration box: legacy unit file on disk, unit running.
	legacyPath := legacyUpgraderUserUnitPath()
	if err := os.WriteFile(legacyPath, []byte("[Unit]\nDescription=StatBus Upgrade Service\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	legacy := f.unit("statbus-upgrade@test.service")
	legacy.loadState = "loaded"
	legacy.activeState = "active"
	legacy.enabled = "enabled"
	legacy.mainPID = 4242

	instance, err := installUpgraderUnit(dir, false, false)
	if err != nil {
		t.Fatal(err)
	}
	if instance != "statbus-upgrader@test.service" {
		t.Fatalf("instance = %q, want statbus-upgrader@test.service", instance)
	}

	// Legacy unit: stopped under the lock, disabled, deleted.
	if legacy.activeState != "inactive" || legacy.mainPID != 0 {
		t.Errorf("legacy unit must be stopped (state=%s pid=%d)", legacy.activeState, legacy.mainPID)
	}
	if legacy.enabled != "disabled" {
		t.Error("legacy unit must be disabled")
	}
	if _, statErr := os.Stat(legacyPath); !os.IsNotExist(statErr) {
		t.Error("legacy unit file must be deleted")
	}
	// Exactly one unit file remains: the new one, byte-identical to the template.
	written, err := os.ReadFile(unitfloor.UserUnitPath())
	if err != nil {
		t.Fatal(err)
	}
	if string(written) != upgraderTestTemplate {
		t.Error("installed unit must be byte-identical to the repo template")
	}
	entries, err := os.ReadDir(upgraderUserUnitDir())
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "statbus-upgrader@.service" {
		names := []string{}
		for _, e := range entries {
			names = append(names, e.Name())
		}
		t.Errorf("exactly one unit must remain (statbus-upgrader@.service), found %v", names)
	}
	if got := f.unit("statbus-upgrader@test.service").enabled; got != "enabled" {
		t.Errorf("new unit must be enabled, got %q", got)
	}
	// The migration's lock is released afterwards.
	if upgrade.IsFlockHeld(dir) {
		t.Error("the migration's upgrade lock must be released")
	}
}

// TestUpgraderInstallMigrationOrdering pins the owner-directed ordering
// (STATBUS-527): the new unit is written and enabled BEFORE the old one is
// touched, the old unit's stop runs only while the upgrade lock is held, and
// the box ends with exactly one unit. A failure before the stop leaves the old
// unit fully intact.
func TestUpgraderInstallMigrationOrdering(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)

	legacyPath := legacyUpgraderUserUnitPath()
	if err := os.WriteFile(legacyPath, []byte("[Unit]\nDescription=old\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	legacy := f.unit("statbus-upgrade@test.service")
	legacy.loadState = "loaded"
	legacy.activeState = "active"
	legacy.enabled = "enabled"
	legacy.mainPID = 4242

	// Record the event sequence with lock state at the legacy stop.
	var events []string
	stopHeldLock := false
	origRun := f.run
	_ = origRun
	wrapped := func(args ...string) (string, error) {
		joined := strings.Join(args, " ")
		switch {
		case strings.HasPrefix(joined, "stop statbus-upgrade@"):
			stopHeldLock = upgrade.IsFlockHeld(dir)
			events = append(events, "stop-legacy")
		case strings.HasPrefix(joined, "disable statbus-upgrade@"):
			events = append(events, "disable-legacy")
		case strings.HasPrefix(joined, "enable statbus-upgrader@"):
			events = append(events, "enable-new")
		case joined == "daemon-reload":
			events = append(events, "daemon-reload")
		}
		return f.run(args...)
	}
	upgraderSystemctl = wrapped
	t.Cleanup(func() { upgraderSystemctl = f.run })

	if _, err := installUpgraderUnit(dir, false, false); err != nil {
		t.Fatal(err)
	}

	// Order: write (daemon-reload #1) + enable new, THEN stop + disable legacy,
	// THEN retire (daemon-reload #2).
	idx := func(needle string) int {
		for i, e := range events {
			if e == needle {
				return i
			}
		}
		return -1
	}
	reloadFirst, enableNew, stopLegacy, disableLegacy := idx("daemon-reload"), idx("enable-new"), idx("stop-legacy"), idx("disable-legacy")
	if reloadFirst < 0 || enableNew < 0 || stopLegacy < 0 || disableLegacy < 0 {
		t.Fatalf("missing events: %v", events)
	}
	if reloadFirst >= enableNew || enableNew >= stopLegacy || stopLegacy >= disableLegacy {
		t.Fatalf("ordering must be write+enable new → stop old → disable old, got %v", events)
	}
	if !stopHeldLock {
		t.Error("the legacy unit's stop must run while the migration holds the upgrade lock")
	}
	if upgrade.IsFlockHeld(dir) {
		t.Error("the lock must be released when the migration returns")
	}
}

// TestUpgraderInstallFixupLeavesLegacyAlone: inside the post-upgrade fixup the
// legacy unit is THIS process's parent — the install writes and enables the
// new unit but must not stop, disable or delete the old one. The running
// upgrader completes the handover itself afterwards (start new → retire old →
// stop self), under the upgrade lock — see
// TestHandoffToRenamedUpgraderUnit_OrderingAndLock in internal/upgrade.
func TestUpgraderInstallFixupLeavesLegacyAlone(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)

	legacyPath := legacyUpgraderUserUnitPath()
	if err := os.WriteFile(legacyPath, []byte("[Unit]\nDescription=old\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	legacy := f.unit("statbus-upgrade@test.service")
	legacy.loadState = "loaded"
	legacy.activeState = "active"
	legacy.enabled = "enabled"
	legacy.mainPID = 4242

	if _, err := installUpgraderUnit(dir, true, true); err != nil {
		t.Fatal(err)
	}
	if legacy.activeState != "active" || legacy.mainPID != 4242 {
		t.Error("fixup install must NOT stop the legacy unit it runs inside")
	}
	if legacy.enabled != "enabled" {
		t.Error("fixup install must NOT disable the legacy unit — the daemon's handover retires it only after the new unit started")
	}
	if _, statErr := os.Stat(legacyPath); statErr != nil {
		t.Error("fixup install must NOT delete the legacy unit file")
	}
	// The new unit is still written and enabled (the ordinary reconcile).
	written, err := os.ReadFile(unitfloor.UserUnitPath())
	if err != nil {
		t.Fatal(err)
	}
	if string(written) != upgraderTestTemplate {
		t.Error("installed unit must be byte-identical to the repo template")
	}
	if got := f.unit("statbus-upgrader@test.service").enabled; got != "enabled" {
		t.Errorf("new unit must be enabled, got %q", got)
	}
}

// TestUpgraderInstallRefusesMigrationWhileUpgradeHoldsLock: `sb upgrader
// install` on a legacy box while an upgrade runs must refuse rather than stop
// the unit out from under the upgrade.
func TestUpgraderInstallRefusesMigrationWhileUpgradeHoldsLock(t *testing.T) {
	dir := upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)
	if err := os.WriteFile(legacyUpgraderUserUnitPath(), []byte("[Unit]\nDescription=old\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	legacy := f.unit("statbus-upgrade@test.service")
	legacy.loadState = "loaded"
	legacy.activeState = "active"
	legacy.mainPID = 4242

	holder, err := upgrade.AcquireInstallFlag(dir, "upgrade-in-flight")
	if err != nil {
		t.Fatal(err)
	}
	defer upgrade.ReleaseInstallFlag(holder)

	if _, err := installUpgraderUnit(dir, false, false); err == nil {
		t.Fatal("migration must refuse while an upgrade holds the lock")
	}
	if f.called("stop") {
		t.Fatal("a refused migration must never stop the unit")
	}
	if legacy.activeState != "active" {
		t.Fatal("the legacy unit must still be running after a refused migration")
	}
}

// ── AC1: start / status ───────────────────────────────────────────────────

// TestUpgraderStartRequiresInstall: start on a box with no unit fails and
// names the remedy.
func TestUpgraderStartRequiresInstall(t *testing.T) {
	upgraderFixture(t, upgraderTestTemplate)
	installFakeSystemd(t)
	err := upgraderStartCmd.RunE(nil, nil)
	if err == nil || !strings.Contains(err.Error(), "sb upgrader install") {
		t.Fatalf("start without a unit must point at sb upgrader install, got: %v", err)
	}
}

// TestUpgraderStartStartsTheUnit: with a recorded installed unit, start
// activates it.
func TestUpgraderStartStartsTheUnit(t *testing.T) {
	upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)
	u := f.unit("statbus-upgrader@test.service")
	u.loadState = "loaded"
	u.activeState = "inactive"
	if err := os.WriteFile(unitfloor.UserUnitPath(), []byte(upgraderTestTemplate), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := upgraderStartCmd.RunE(nil, nil); err != nil {
		t.Fatal(err)
	}
	if u.activeState != "active" {
		t.Fatal("start must activate the unit")
	}
}

// TestFormatUpgraderStatus pins the status rendering: unit state, the program
// the main process runs, and the disk comparison — including the legacy note
// and the stale-binary case.
func TestFormatUpgraderStatus(t *testing.T) {
	dir := t.TempDir()
	match := true
	mismatch := false

	running := formatUpgraderStatus(dir, upgraderObservation{
		instance: "statbus-upgrader@test.service", loadState: "loaded",
		activeState: "active", enabled: "enabled", mainPID: 4242,
		exeTarget: "/home/test/statbus/sb", matchesDisk: &match,
	})
	for _, want := range []string{"statbus-upgrader@test.service", "active", "enabled", "4242", "/home/test/statbus/sb", "runs the program on disk"} {
		if !strings.Contains(running, want) {
			t.Errorf("status of a healthy upgrader must contain %q:\n%s", want, running)
		}
	}

	stale := formatUpgraderStatus(dir, upgraderObservation{
		instance: "statbus-upgrader@test.service", loadState: "loaded",
		activeState: "active", enabled: "enabled", mainPID: 4242,
		exeTarget: "/home/test/statbus/sb", matchesDisk: &mismatch,
	})
	if !strings.Contains(stale, "DIFFERENT") || !strings.Contains(stale, "restart") {
		t.Errorf("status of a stale upgrader must say DIFFERENT and name the remedy:\n%s", stale)
	}

	legacy := formatUpgraderStatus(dir, upgraderObservation{
		instance: "statbus-upgrade@test.service", loadState: "loaded",
		activeState: "active", enabled: "enabled", legacy: true,
	})
	if !strings.Contains(legacy, "old unit name") || !strings.Contains(legacy, "./sb install") {
		t.Errorf("status of a pre-migration box must name the old unit and the migration path:\n%s", legacy)
	}

	absent := formatUpgraderStatus(dir, upgraderObservation{
		instance: "statbus-upgrader@test.service", loadState: "not-found",
	})
	if !strings.Contains(absent, "not installed") || !strings.Contains(absent, "sb upgrader install") {
		t.Errorf("status without a unit must say not installed and name the remedy:\n%s", absent)
	}
}

// ── Resolution across the rename ──────────────────────────────────────────

func TestResolveUpgraderInstance(t *testing.T) {
	upgraderFixture(t, upgraderTestTemplate)
	f := installFakeSystemd(t)

	// Nothing installed → the new name (what a fresh install writes).
	if got := resolveUpgraderInstance(); got != "statbus-upgrader@test.service" {
		t.Fatalf("fresh box resolves to the new name, got %q", got)
	}
	// Only the legacy unit installed → the legacy name.
	if err := os.WriteFile(legacyUpgraderUserUnitPath(), []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := resolveUpgraderInstance(); got != "statbus-upgrade@test.service" {
		t.Fatalf("legacy-only box resolves to the legacy name, got %q", got)
	}
	// Mid-migration: both files → the new name wins.
	if err := os.WriteFile(unitfloor.UserUnitPath(), []byte("new"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := resolveUpgraderInstance(); got != "statbus-upgrader@test.service" {
		t.Fatalf("mid-migration box resolves to the new name, got %q", got)
	}
	// Files gone but a deleted unit still runs → address the runner.
	if err := os.Remove(legacyUpgraderUserUnitPath()); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(unitfloor.UserUnitPath()); err != nil {
		t.Fatal(err)
	}
	legacy := f.unit("statbus-upgrade@test.service")
	legacy.loadState = "loaded"
	legacy.activeState = "active"
	legacy.mainPID = 4242
	if got := resolveUpgraderInstance(); got != "statbus-upgrade@test.service" {
		t.Fatalf("a deleted-but-running legacy unit is still addressed, got %q", got)
	}
}

// ── AC7: one implementation ───────────────────────────────────────────────

// TestInstallStepAndHelpersShareTheUpgraderImplementation pins AC7: the
// "Upgrader" install step, install's deferred final action, and the
// post-inline-upgrade restart all call the shared functions in upgrader.go —
// there is no second copy of unit writing or start/stop.
func TestInstallStepAndHelpersShareTheUpgraderImplementation(t *testing.T) {
	installSrc, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	stepBody := funcBody(t, string(installSrc), "func runInstallService(")
	if !strings.Contains(stepBody, "installUpgraderUnit(dir, true") {
		t.Error("the install step must install the unit through installUpgraderUnit (upgrader.go)")
	}
	if strings.Contains(stepBody, `"statbus-upgrade.service"`) || strings.Contains(stepBody, `copyFile(`) {
		t.Error("the install step must not carry its own copy of unit writing")
	}
	dispatchBody := funcBody(t, string(installSrc), "var dispatchUpgradeDaemonFinalAction = func(")
	if !strings.Contains(dispatchBody, "submitUpgraderAction(") {
		t.Error("install's final action must dispatch through submitUpgraderAction (upgrader.go)")
	}
	upgradeSrc, err := os.ReadFile("install_upgrade.go")
	if err != nil {
		t.Fatal(err)
	}
	restartBody := funcBody(t, string(upgradeSrc), "func restartUpgradeService(")
	if !strings.Contains(restartBody, "submitUpgraderAction(") {
		t.Error("restartUpgradeService must restart through submitUpgraderAction (upgrader.go)")
	}
}
