package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-527: each long-running StatBus program has a NOUN command group, and
// `sb upgrade ...` keeps only the verbs that act on upgrades (apply, check,
// schedule, dismiss, list, register, trust-key). The program that performs
// those upgrades is the UPGRADER, and this file is its home:
//
//	sb upgrader run      — the long-running process systemd starts
//	sb upgrader install  — write + enable the systemd user unit (migration incl.)
//	sb upgrader start    — start the unit
//	sb upgrader stop     — stop the unit under the upgrade lock, waiting for exit
//	sb upgrader status   — read-only: unit state, program, disk match
//
// ONE IMPLEMENTATION RULE (AC7): the "Upgrader" step of `./sb install` and the
// restart helpers (restartUpgradeService, dispatchUpgradeDaemonFinalAction)
// call the functions in this file. There is no second copy of unit writing or
// start/stop anywhere else.
//
// THE RENAME: the systemd unit was `statbus-upgrade@.service` before
// STATBUS-527 and is `statbus-upgrader@.service` now. installUpgraderUnit
// migrates a box that still carries the old unit: stop under the lock,
// disable, delete, install the new one — exactly one unit remains. The old
// unit's ExecStart runs `sb upgrade service`, which stays as a hidden alias of
// `sb upgrader run` until every supported box has migrated (its removal is the
// follow-up ticket named in STATBUS-527 AC9).
const (
	upgraderUnitBase       = "statbus-upgrader"
	legacyUpgraderUnitBase = "statbus-upgrade"
)

// upgraderPlatform is the platform gate for the upgrader commands — a
// variable so tests can exercise command logic off Linux.
var upgraderPlatform = runtime.GOOS

// upgraderSystemctl is the systemd seam for the upgrader's lifecycle
// operations: one runner so tests can drive the commands against a recorded
// systemd state instead of a live user manager. Arguments DO NOT include
// `--user`; it is prepended here.
var upgraderSystemctl = func(args ...string) (string, error) {
	out, err := exec.Command("systemctl", append([]string{"--user"}, args...)...).CombinedOutput()
	return string(out), err
}

// upgraderUserUnitDir is where user-level units live for this box's user.
func upgraderUserUnitDir() string {
	return filepath.Join(os.Getenv("HOME"), ".config", "systemd", "user")
}

// legacyUpgraderUserUnitPath is where the PRE-STATBUS-527 unit was installed.
// Its continued existence on a box is what triggers the migration in
// installUpgraderUnit.
func legacyUpgraderUserUnitPath() string {
	return filepath.Join(upgraderUserUnitDir(), legacyUpgraderUnitBase+"@.service")
}

// upgraderUnitFileExists reports whether a unit file exists at path.
func upgraderUnitFileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// upgraderUnitActive reports whether systemd currently considers the unit
// active (or activating — a unit mid-start is alive for our purposes).
func upgraderUnitActive(instance string) bool {
	if instance == "" {
		return false
	}
	out, _ := upgraderSystemctl("is-active", instance)
	state := strings.TrimSpace(out)
	return state == "active" || state == "activating"
}

// upgraderUnitLoadState reports the unit's LoadState ("loaded", "not-found",
// ...). "" when the query itself failed.
func upgraderUnitLoadState(instance string) string {
	out, err := upgraderSystemctl("show", instance, "-p", "LoadState", "--value")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(out)
}

// resolveUpgraderInstance picks the unit instance name lifecycle operations
// should address on this box, across the STATBUS-527 rename:
//   - a RUNNING unit always wins over a merely-installed file. The
//     post-upgrade fixup deliberately writes and enables the new unit while
//     the legacy unit still runs (the handoff may be deferred or failed), and
//     stop/status/quiesce must address the daemon that actually runs —
//     stopping the inactive new unit while the legacy daemon lives would be a
//     false success (review H1);
//   - otherwise the new unit whenever its file is installed (post-migration
//     steady state);
//   - the legacy unit when only it is installed (pre-migration box);
//   - with neither file, the new name (what a fresh install will write).
func resolveUpgraderInstance() string {
	current := serviceInstance("")
	legacy := legacyServiceInstance("")
	if current == "" {
		return ""
	}
	if upgraderUnitActive(current) {
		return current
	}
	if upgraderUnitActive(legacy) {
		return legacy
	}
	newInstalled := upgraderUnitFileExists(unitfloor.UserUnitPath())
	legacyInstalled := upgraderUnitFileExists(legacyUpgraderUserUnitPath())
	switch {
	case newInstalled:
		return current
	case legacyInstalled:
		return legacy
	}
	return current
}

// ── Shared unit operations ─────────────────────────────────────────────────

// writeUpgraderUnitFile copies the repo template (ops/statbus-upgrader.service)
// verbatim to the user unit dir and reloads systemd. The %h/%i/%u specifiers
// resolve at systemd runtime, so the copy is a byte copy and the on-disk file
// must be byte-identical to the template (that identity is the drift check —
// see unitfloor).
func writeUpgraderUnitFile(dir string) error {
	if err := os.MkdirAll(upgraderUserUnitDir(), 0755); err != nil {
		return fmt.Errorf("create systemd user dir: %w", err)
	}
	serviceFile := filepath.Join(dir, "ops", upgraderUnitBase+".service")
	destFile := unitfloor.UserUnitPath()
	fmt.Printf("  Copying %s → %s\n", filepath.Base(serviceFile), destFile)
	if err := copyFile(serviceFile, destFile); err != nil {
		return fmt.Errorf("copy unit file: %w", err)
	}
	fmt.Println("  Running systemctl --user daemon-reload")
	if out, err := upgraderSystemctl("daemon-reload"); err != nil {
		return fmt.Errorf("systemctl --user daemon-reload: %w: %s", err, strings.TrimSpace(out))
	}
	return nil
}

// enableUpgraderUnit enables the unit and VERIFIES the boot-enable symlink was
// actually created. Bug observed on rune 2026-04-22: `systemctl --user enable
// --now` exited 0 but the default.target.wants/ symlink was missing — service
// ran but would not start after a reboot. Fail loudly so the box does not
// regress on its next reboot.
func enableUpgraderUnit(instance string) error {
	fmt.Printf("  Enabling %s\n", instance)
	if out, err := upgraderSystemctl("enable", instance); err != nil {
		return serviceFailureWithJournal("enable the upgrader", instance, true,
			fmt.Errorf("%w: %s", err, strings.TrimSpace(out)))
	}
	out, isEnabledErr := upgraderSystemctl("is-enabled", instance)
	state := strings.TrimSpace(out)
	if state != "enabled" {
		return fmt.Errorf("enable reported success but is-enabled=%q (err=%v); the upgrader will not start on boot — investigate systemctl user-bus / loginctl linger", state, isEnabledErr)
	}
	return nil
}

// submitUpgraderAction issues a lifecycle action (start, restart) against the
// unit, clearing a stale failed state first so a start-rate-limited unit can
// recover. This is the ONE start/restart primitive: `sb upgrader start` and
// install's deferred final action both go through it.
//
// noBlock must be true while the caller still holds the upgrade lock (the
// install step table does, until process exit): a blocking start of the
// Type=notify unit would wait for READY=1 while the booting daemon's bounded
// STATBUS-432 wait blocks on that same lock — a self-deadlock against our own
// TimeoutStartSec.
func submitUpgraderAction(instance, action string, noBlock bool) error {
	// A unit that hit systemd's start-rate limit refuses every further start
	// until its failed state is cleared. Harmless on a healthy unit.
	_, _ = upgraderSystemctl("reset-failed", instance)
	args := []string{}
	if noBlock {
		args = append(args, "--no-block")
	}
	args = append(args, action, instance)
	if out, err := upgraderSystemctl(args...); err != nil {
		return serviceFailureWithJournal(action+" the upgrader", instance, true,
			fmt.Errorf("%w: %s", err, strings.TrimSpace(out)))
	}
	return nil
}

// startUpgraderUnit starts the unit and waits for the start job to finish.
// Used by `sb upgrader start`.
func startUpgraderUnit(instance string) error {
	return submitUpgraderAction(instance, "start", false)
}

// upgraderStopPollInterval / upgraderStopVerifyTimeout bound the post-stop
// verification: `systemctl stop` blocks until the stop job completes, so the
// MainPID poll below is a belt on top, not the primary wait. Variables (not
// constants) so tests can shrink the timeout.
var (
	upgraderStopPollInterval  = 200 * time.Millisecond
	upgraderStopVerifyTimeout = 10 * time.Second
)

// upgraderMainPID reads the unit's MainPID; 0 when the unit has no main
// process (stopped) or the property cannot be read as a number.
func upgraderMainPID(instance string) int {
	out, err := upgraderSystemctl("show", instance, "-p", "MainPID", "--value")
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(out))
	return pid
}

// stopUpgraderUnitAndWait stops the unit and returns only after its main
// process has exited. A no-op when the unit is not installed. The caller must
// hold the upgrade lock (or have established that no upgrade can be in flight)
// BEFORE calling: a stop that interrupted a live upgrade would trigger a
// rollback — a snapshot restore over the live database.
func stopUpgraderUnitAndWait(instance string) error {
	if instance == "" {
		return fmt.Errorf("could not determine the upgrader's unit name (USER is unset)")
	}
	if upgraderUnitLoadState(instance) == "not-found" && !upgraderUnitActive(instance) {
		fmt.Printf("The upgrader unit %s is not installed; nothing to stop.\n", instance)
		return nil
	}
	fmt.Printf("Stopping the upgrader (%s); waiting for its main process to exit.\n", instance)
	if out, err := upgraderSystemctl("stop", instance); err != nil {
		return serviceFailureWithJournal("stop the upgrader", instance, true,
			fmt.Errorf("%w: %s", err, strings.TrimSpace(out)))
	}
	deadline := time.Now().Add(upgraderStopVerifyTimeout)
	for {
		if pid := upgraderMainPID(instance); pid == 0 {
			fmt.Println("The upgrader has stopped.")
			return nil
		}
		if !time.Now().Before(deadline) {
			return fmt.Errorf("the upgrader unit %s still has a main process after `systemctl stop` returned; investigate with `systemctl --user status %s`", instance, instance)
		}
		time.Sleep(upgraderStopPollInterval)
	}
}

// ── Migration from the pre-STATBUS-527 unit name ──────────────────────────

// legacyUpgraderUnitPresent reports whether the box still carries the old
// `statbus-upgrade@` unit: its unit file on disk, or a unit systemd still
// knows (a deleted unit file leaves the unit loaded while it runs).
func legacyUpgraderUnitPresent() bool {
	if upgraderUnitFileExists(legacyUpgraderUserUnitPath()) {
		return true
	}
	legacy := legacyServiceInstance("")
	return legacy != "" && upgraderUnitLoadState(legacy) == "loaded"
}

// retireLegacyUpgraderUnit disables and deletes the pre-STATBUS-527 unit and
// reloads systemd. It never stops a process: callers either stopped the unit
// first (installUpgraderUnit) or ARE the unit's own daemon about to stop
// itself (the self-upgrade handover, via `sb upgrader retire-legacy-unit`).
func retireLegacyUpgraderUnit(dir string) error {
	legacy := legacyServiceInstance(dir)
	if legacy == "" || !legacyUpgraderUnitPresent() {
		return nil
	}
	fmt.Printf("  Retiring the pre-rename upgrader unit: %s\n", legacy)
	if out, err := upgraderSystemctl("disable", legacy); err != nil {
		// Best-effort: the unit file deletion below is the load-bearing half;
		// a stale wants symlink without a unit file is inert.
		fmt.Printf("  Note: systemctl --user disable %s failed: %v: %s (continuing — removing the unit file is what counts)\n", legacy, err, strings.TrimSpace(out))
	}
	if err := os.Remove(legacyUpgraderUserUnitPath()); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove legacy upgrader unit file: %w", err)
	}
	if out, err := upgraderSystemctl("daemon-reload"); err != nil {
		return fmt.Errorf("systemctl --user daemon-reload after removing the legacy unit: %w: %s", err, strings.TrimSpace(out))
	}
	return nil
}

// migrateLegacyUpgraderUnit removes the pre-STATBUS-527 unit so the box ends
// with exactly one: statbus-upgrader@. The caller holds the upgrade lock
// (installUpgraderUnit arranged it), so no upgrade can be in flight and the
// stop cannot interrupt one — a stop that did would trigger a rollback, a
// snapshot restore over the live database.
//
// Ordering (owner direction, STATBUS-527): the NEW unit is already written and
// enabled before the old one is touched, so a failure mid-migration leaves the
// old unit fully intact and the next attempt retries.
func migrateLegacyUpgraderUnit(dir string) error {
	legacy := legacyServiceInstance(dir)
	if legacy == "" || !legacyUpgraderUnitPresent() {
		return nil
	}
	fmt.Printf("  Migrating the upgrader unit: %s → %s\n", legacy, serviceInstance(dir))
	if err := stopUpgraderUnitAndWait(legacy); err != nil {
		return err
	}
	return retireLegacyUpgraderUnit(dir)
}

// installUpgraderUnit is the ONE implementation of "the box runs the upgrader
// under systemd": write the unit file, reload systemd, clear a stale failed
// state, enable + verify — and, when the box still carries the pre-STATBUS-527
// unit, migrate it so exactly one unit remains. It never STARTS the unit —
// starting is `sb upgrader start` (or install's deferred final action, or the
// upgrader's own self-upgrade handover).
//
// Locking and regimes:
//   - Ordinary (install step: lockHeldByCaller=true; `sb upgrader install`:
//     acquires here): the migration runs under the upgrade lock — while an
//     upgrade holds it, this refuses with a wait message. Ordering: the new
//     unit is written and enabled BEFORE the old one is stopped, disabled and
//     deleted, so a failure mid-migration leaves the old unit intact.
//   - insideUnit (the post-upgrade fixup runs as a child of the legacy unit's
//     daemon): the legacy unit is NOT touched here at all. The daemon itself
//     completes the handover afterwards, under the upgrade lock, in
//     start-new-then-retire-old order — see
//     Service.handoffToRenamedUpgraderUnit in internal/upgrade.
func installUpgraderUnit(dir string, lockHeldByCaller, insideUnit bool) (string, error) {
	instance := serviceInstance(dir)
	if instance == "" {
		return "", fmt.Errorf("could not determine the upgrader's unit name (USER is unset)")
	}

	migrate := legacyUpgraderUnitPresent() && !insideUnit
	var lock *upgrade.FlagLock
	if migrate && !lockHeldByCaller {
		l, err := upgrade.AcquireLifecycleFlag(dir, "operator:upgrader-install")
		if err != nil {
			return "", fmt.Errorf("cannot migrate the upgrader unit: %w", err)
		}
		lock = l
		defer upgrade.ReleaseInstallFlag(lock)
	}

	// Write + enable the NEW unit first (see the ordering note above).
	if err := writeUpgraderUnitFile(dir); err != nil {
		return "", err
	}

	// Recovery: a unit in `failed` state from a prior crashed upgrade (e.g. the
	// rune wedge — StartLimitBurst after repeated SIGKILL → restart cycles)
	// refuses later start requests. Probe and reset-failed first. Idempotent:
	// a healthy unit reports active/inactive and the reset is skipped.
	if probeOut, probeErr := upgraderSystemctl("show", instance, "--property=ActiveState", "--property=Result"); probeErr == nil {
		if strings.Contains(probeOut, "ActiveState=failed") || strings.Contains(probeOut, "Result=start-limit-hit") {
			fmt.Printf("  Unit %s is in failed state — running reset-failed\n", instance)
			if out, err := upgraderSystemctl("reset-failed", instance); err != nil {
				return "", serviceFailureWithJournal("reset-failed the upgrader", instance, true,
					fmt.Errorf("%w: %s", err, strings.TrimSpace(out)))
			}
		}
	}

	if err := enableUpgraderUnit(instance); err != nil {
		return "", err
	}

	if migrate {
		if err := migrateLegacyUpgraderUnit(dir); err != nil {
			return "", err
		}
	}
	return instance, nil
}

// ── Observation (status) ──────────────────────────────────────────────────

// upgraderObservation is what the box shows about the upgrader: unit state,
// and — when it runs — the program its main process executes and whether that
// program is the ./sb on disk.
type upgraderObservation struct {
	instance    string
	loadState   string // "loaded", "not-found", "" (query failed)
	activeState string
	enabled     string
	mainPID     int
	exeLink     string // /proc/<pid>/exe — read THROUGH the symlink for content compare
	exeTarget   string // the symlink target, cleaned of a trailing " (deleted)"
	exeDeleted  bool   // the program file was replaced/removed after the process started
	matchesDisk *bool  // nil: comparison not possible (no process, unreadable)
	legacy      bool   // the box still runs the pre-STATBUS-527 unit name
}

// observeUpgrader reads the upgrader's state from systemd and /proc. Read-only.
// Off Linux it reports a not-applicable observation. install_stale_daemon.go's
// observeRunningDaemon is a thin adapter over this, so install and
// `sb upgrader status` never disagree about what runs.
var observeUpgrader = func(dir string) upgraderObservation {
	obs := upgraderObservation{}
	if runtime.GOOS != "linux" {
		return obs
	}
	obs.instance = resolveUpgraderInstance()
	if obs.instance == "" {
		return obs
	}
	obs.legacy = strings.HasPrefix(obs.instance, legacyUpgraderUnitBase+"@")
	obs.loadState = upgraderUnitLoadState(obs.instance)
	if out, err := upgraderSystemctl("is-active", obs.instance); err == nil || strings.TrimSpace(out) != "" {
		obs.activeState = strings.TrimSpace(out)
	}
	if out, err := upgraderSystemctl("is-enabled", obs.instance); err == nil {
		obs.enabled = strings.TrimSpace(out)
	}
	obs.mainPID = upgraderMainPID(obs.instance)
	if obs.activeState != "active" || obs.mainPID == 0 {
		return obs
	}
	obs.exeLink = filepath.Join("/proc", strconv.Itoa(obs.mainPID), "exe")
	target, err := os.Readlink(obs.exeLink)
	if err != nil {
		return obs
	}
	obs.exeTarget = strings.TrimSuffix(target, " (deleted)")
	obs.exeDeleted = strings.HasSuffix(target, " (deleted)")
	if !obs.exeDeleted {
		if same, serr := sameFileContent(obs.exeLink, filepath.Join(dir, "sb")); serr == nil {
			obs.matchesDisk = &same
		}
	}
	return obs
}

func formatUpgraderStatus(dir string, obs upgraderObservation) string {
	var b strings.Builder
	if obs.instance == "" {
		if runtime.GOOS != "linux" {
			fmt.Fprintln(&b, "The upgrader is managed by systemd, which does not exist on this platform.")
		} else {
			fmt.Fprintln(&b, "The upgrader's unit name cannot be determined (USER is unset).")
		}
		return b.String()
	}
	fmt.Fprintf(&b, "Unit:    %s\n", obs.instance)
	state := obs.activeState
	if state == "" {
		state = "unknown"
	}
	if obs.loadState == "not-found" {
		fmt.Fprintf(&b, "State:   not installed\n")
		fmt.Fprintf(&b, "Install it with: ./sb upgrader install (or %s)\n", upgrade.InstallCommand(dir))
	} else {
		enabled := obs.enabled
		if enabled == "" {
			enabled = "unknown"
		}
		fmt.Fprintf(&b, "State:   %s (enabled: %s)\n", state, enabled)
	}
	if obs.mainPID != 0 {
		fmt.Fprintf(&b, "Main PID: %d\n", obs.mainPID)
		program := obs.exeTarget
		if program == "" {
			program = "(unreadable)"
		}
		if obs.exeDeleted {
			program += " (deleted)"
		}
		fmt.Fprintf(&b, "Program: %s\n", program)
		disk := filepath.Join(dir, "sb")
		switch {
		case obs.exeDeleted:
			fmt.Fprintf(&b, "On disk: %s — DIFFERENT: the running program was replaced on disk; restart the upgrader (./sb upgrader stop && ./sb upgrader start, or %s)\n", disk, upgrade.InstallCommand(dir))
		case obs.matchesDisk == nil:
			fmt.Fprintf(&b, "On disk: %s — comparison unavailable\n", disk)
		case *obs.matchesDisk:
			fmt.Fprintf(&b, "On disk: %s — the upgrader runs the program on disk\n", disk)
		default:
			fmt.Fprintf(&b, "On disk: %s — DIFFERENT: the upgrader runs a different program; restart it (./sb upgrader stop && ./sb upgrader start, or %s)\n", disk, upgrade.InstallCommand(dir))
		}
	}
	if obs.legacy {
		fmt.Fprintf(&b, "Note:    this box still uses the old unit name (%s). Run %s to migrate to %s.\n",
			legacyUpgraderUnitBase+"@.service", upgrade.InstallCommand(dir), upgraderUnitBase+"@.service")
	}
	return b.String()
}

// ── Commands ───────────────────────────────────────────────────────────────

var upgraderCmd = &cobra.Command{
	Use:     "upgrader",
	Short:   "Manage the upgrader — the program that performs upgrades",
	GroupID: operationsGroupID,
	Long: `The upgrader is the long-running program that discovers, prepares and
performs software upgrades on this box. systemd manages it on the host.

  run       The long-running process itself (this is what the unit starts)
  install   Write + enable the systemd unit (migrates a pre-rename unit)
  start     Start the unit
  stop      Stop the unit under the upgrade lock, waiting for its exit
  status    Show the unit's state and whether it runs the ./sb on disk

Actions ON upgrades (apply, check, schedule, dismiss, list) live under
'sb upgrade'.`,
}

var upgraderRunCmd = &cobra.Command{
	Use:   "run",
	Short: "Run the upgrader (long-running process, started by systemd)",
	Long: `Starts the upgrader, which:
  - Polls GitHub Releases for new versions
  - Pre-downloads Docker images
  - Listens for NOTIFY upgrade_check and upgrade_apply
  - Executes scheduled upgrades with backup and rollback

Typically run via systemd (ops/statbus-upgrader.service).`,
	// systemd entrypoint. If a previous upgrade rolled back leaving cli/
	// ahead of the binary, stalenessGuard rebuilds + re-execs instead of
	// crash-looping the upgrader. See cli/cmd/root.go.
	Annotations: map[string]string{"selfheal": "true"},
	RunE:        upgradeServiceRunE,
}

var upgraderInstallCmd = &cobra.Command{
	Use:   "install",
	Short: "Write and enable the upgrader's systemd unit",
	Long: `Writes the systemd user unit (statbus-upgrader@.service), reloads
systemd and enables the unit. This is the code behind the "Upgrader" step of
'sb install', which calls it.

A box still carrying the pre-rename unit (statbus-upgrade@.service) is
migrated: the new unit is written and enabled first, then the old unit is
stopped under the upgrade lock, disabled and deleted, so exactly one unit
remains. The migration refuses while an upgrade holds the lock — wait for the
upgrade to finish. Does not START the unit: use 'sb upgrader start'.

Inside the post-upgrade fixup (STATBUS_POST_UPGRADE_FIXUP=1, set by the
upgrader itself) the legacy unit is left alone; the running upgrader completes
the handover itself under the upgrade lock.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if upgraderPlatform != "linux" {
			return fmt.Errorf("the upgrader's systemd unit can only be installed on Linux")
		}
		dir := config.ProjectDir()
		insideUnit := postUpgradeFixup || os.Getenv("STATBUS_POST_UPGRADE_FIXUP") == "1"
		// lockHeldByCaller=false suffices: in the insideUnit regime the legacy
		// unit is untouched, so no lock is taken either way.
		instance, err := installUpgraderUnit(dir, false, insideUnit)
		if err != nil {
			return err
		}
		fmt.Printf("  Upgrader installed and enabled: %s\n", instance)
		fmt.Println("  Start it with: ./sb upgrader start")
		return nil
	},
}

var upgraderStartNoBlock bool

// upgraderStartUnit pins the exact unit to start. Hidden: the ONLY legitimate
// user is the self-upgrade unit handover, which must start the NEW unit while
// the legacy unit is still the active one — generic resolution (H1) prefers
// the running unit, which is exactly the wrong answer there.
var upgraderStartUnit string

var upgraderStartCmd = &cobra.Command{
	Use:   "start",
	Short: "Start the upgrader's systemd unit",
	Long: `Starts the upgrader's systemd unit and waits for the start job.

--no-block submits the start and returns immediately. The upgrader uses this
itself during the self-upgrade unit handover, where the new unit's first boot
may briefly lose the daemon advisory lock to the still-exiting old process and
be retried by Restart=always.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if upgraderPlatform != "linux" {
			return fmt.Errorf("the upgrader is managed by systemd, which does not exist on this platform")
		}
		instance := upgraderStartUnit
		if instance == "" {
			instance = resolveUpgraderInstance()
		}
		if instance == "" {
			return fmt.Errorf("could not determine the upgrader's unit name (USER is unset)")
		}
		if upgraderUnitLoadState(instance) == "not-found" {
			return fmt.Errorf("the upgrader is not installed (no %s unit); run ./sb upgrader install first", instance)
		}
		if err := submitUpgraderAction(instance, "start", upgraderStartNoBlock); err != nil {
			return err
		}
		fmt.Printf("The upgrader is starting (%s).\n", instance)
		return nil
	},
}

// upgraderRetireLegacyCmd is the second half of the self-upgrade unit
// handover (STATBUS-527): disable + delete the pre-rename unit after the new
// one is written, enabled and started. The upgrader runs it on itself while it
// holds the upgrade lock (the STATBUS_POST_UPGRADE_FIXUP=1 env signature marks
// that contract, exactly like the post-upgrade fixup install). Run by hand it
// takes the lock itself and refuses while an upgrade holds it.
var upgraderRetireLegacyCmd = &cobra.Command{
	Use:    "retire-legacy-unit",
	Short:  "Disable and delete the pre-rename statbus-upgrade@ unit (handover step)",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		if upgraderPlatform != "linux" {
			return fmt.Errorf("the upgrader is managed by systemd, which does not exist on this platform")
		}
		return runUpgraderRetireLegacy(config.ProjectDir())
	},
}

// runUpgraderRetireLegacy is `sb upgrader retire-legacy-unit` with the cobra
// shell removed, so tests drive the lock behaviour directly.
func runUpgraderRetireLegacy(dir string) error {
	if os.Getenv("STATBUS_POST_UPGRADE_FIXUP") != "1" {
		lock, err := upgrade.AcquireLifecycleFlag(dir, "operator:upgrader-retire-legacy")
		if err != nil {
			return fmt.Errorf("cannot retire the old upgrader unit: %w", err)
		}
		defer upgrade.ReleaseInstallFlag(lock)
	}
	return retireLegacyUpgraderUnit(dir)
}

// upgraderStopTimeout refusal and lock behaviour are pinned by
// upgrader_test.go: stop REFUSES while an upgrade holds the lock (a stop that
// interrupted one would trigger a rollback — a snapshot restore over the live
// database), and returns only after the unit's main process has exited.
var upgraderStopCmd = &cobra.Command{
	Use:   "stop",
	Short: "Stop the upgrader, waiting for its main process to exit",
	Long: `Stops the upgrader's systemd unit under the upgrade lock (the same
advisory lock 'sb install' uses) and returns only after the unit's main
process has exited.

If an upgrade holds the lock, the stop is refused with a message to wait: a
stop that interrupted a live upgrade would trigger a rollback — a snapshot
restore over the live database. A crashed or parked upgrade's recovery marker
also refuses the stop: recover it first with the install command for this box
('sb install', run from the checkout).

One bounded gap by design: an upgrade claims its row and runs its pre-flight
checks BEFORE it takes the lock. A stop landing in that short, pre-destructive
window still SIGTERMs the daemon; nothing has been mutated yet, so the next
boot simply re-claims the row.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if upgraderPlatform != "linux" {
			return fmt.Errorf("the upgrader is managed by systemd, which does not exist on this platform")
		}
		return runUpgraderStop(config.ProjectDir())
	},
}

// runUpgraderStop is `sb upgrader stop` with the cobra shell removed, so tests
// drive the lock + wait behaviour directly.
func runUpgraderStop(dir string) error {
	instance := resolveUpgraderInstance()
	if instance == "" {
		return fmt.Errorf("could not determine the upgrader's unit name (USER is unset)")
	}
	lock, err := upgrade.AcquireLifecycleFlag(dir, "operator:upgrader-stop")
	if err != nil {
		return fmt.Errorf("the upgrader was not stopped — %w", err)
	}
	defer upgrade.ReleaseInstallFlag(lock)
	return stopUpgraderUnitAndWait(instance)
}

var upgraderStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show the upgrader's unit state and the program it runs",
	Long: `Read-only: shows the unit's state, the program its main process runs
(read from /proc/<MainPID>/exe), and whether that program is the ./sb on disk.
A mismatch means the upgrader is running old code; restart it.

The exit code is the scriptable verdict: 0 when the upgrader is installed,
active and runs the ./sb on disk (or when there is no systemd to judge,
e.g. a development laptop); 1 otherwise — not installed, not active, or
running a different program.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		dir := config.ProjectDir()
		obs := observeUpgrader(dir)
		fmt.Print(formatUpgraderStatus(dir, obs))
		return upgraderStatusVerdict(obs)
	},
}

// upgraderStatusVerdict is the exit-code half of `sb upgrader status` (review
// F4): scripts and harness assertions get a non-zero exit when the upgrader is
// not installed, not active, or running a different program than the ./sb on
// disk. Off Linux (or with an underivable unit name) there is no systemd to
// judge, so the observation is informational and exits 0.
func upgraderStatusVerdict(obs upgraderObservation) error {
	if obs.instance == "" {
		return nil
	}
	if obs.loadState == "not-found" {
		return fmt.Errorf("the upgrader is not installed (no %s unit)", obs.instance)
	}
	if obs.activeState != "active" {
		return fmt.Errorf("the upgrader is not active (state %q)", obs.activeState)
	}
	if obs.exeDeleted || (obs.matchesDisk != nil && !*obs.matchesDisk) {
		return fmt.Errorf("the upgrader runs a different program than the ./sb on disk; restart it")
	}
	return nil
}

func init() {
	upgraderStartCmd.Flags().BoolVar(&upgraderStartNoBlock, "no-block", false, "submit the start and return without waiting for the start job")
	upgraderStartCmd.Flags().StringVar(&upgraderStartUnit, "unit", "", "start exactly this unit (hidden; the self-upgrade handover's start of the NEW unit while the legacy one is still active)")
	_ = upgraderStartCmd.Flags().MarkHidden("unit")
	upgraderCmd.AddCommand(upgraderRunCmd)
	upgraderCmd.AddCommand(upgraderInstallCmd)
	upgraderCmd.AddCommand(upgraderStartCmd)
	upgraderCmd.AddCommand(upgraderStopCmd)
	upgraderCmd.AddCommand(upgraderStatusCmd)
	upgraderCmd.AddCommand(upgraderRetireLegacyCmd)
	rootCmd.AddCommand(upgraderCmd)
}
