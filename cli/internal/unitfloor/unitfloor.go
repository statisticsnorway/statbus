// Package unitfloor answers one question: is this box structurally able to
// follow its channel?
//
// THE INCIDENT (STATBUS-303). demo sat nine days with a stale upgrade page,
// looking healthy, while being structurally unable to ever take the stable
// release automatically. Nothing said so. The silence was the defect — not the
// gap itself, which a human would have fixed in a minute had anything named it.
//
// DETECTION ONLY — NEVER REPAIR. This package reads. It does not write unit
// files, does not run `systemctl start`, does not reconcile. Three reasons,
// settled on the ticket:
//   - The missing piece IS the machinery a self-repair would ride. A box whose
//     service is absent cannot schedule its own fix.
//   - A second watchdog only moves the question to who repairs the watchdog.
//   - Standing self-heal paths are forbidden here: a recurrence must fail
//     loudly with the fix named, never be quietly patched forever.
//
// The repair stays `./sb install` — the product's own idempotent verb, run by
// a human. That verb already knows how to lay the unit down; this package's
// entire job is to make sure nobody has to guess that they should run it.
//
// THE FLOOR IS DERIVED, NOT ASSUMED. An earlier framing of the ticket named a
// `statbus-upgrade-check` unit that has never existed in this product — check
// scheduling is the upgrade service's own internal ticker plus NOTIFY, not a
// systemd timer. Inventing a floor from memory is how you end up alerting on a
// phantom. So the floor here is exactly what the install step-table lays down
// and nothing more: the templated user unit `statbus-upgrade@.service`, byte
// -identical to the repo's copy, with its per-user instance active.
package unitfloor

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// State is the specific way a box can sit below its floor. The states are
// distinct because the remedies and the urgency differ, and because "not
// healthy" alone is exactly the uninformative signal this ticket exists to
// replace.
type State int

const (
	// OK — unit file present, byte-identical to the repo template, instance active.
	OK State = iota
	// NotApplicable — not Linux. Developer laptops have no user units; saying
	// "your scheduler is missing" there would be noise that teaches people to
	// ignore the real message.
	NotApplicable
	// UnknownUser — $USER unset, so the instance name cannot be derived. Not a
	// floor breach: an honest inability to look, reported as such rather than
	// guessed either way.
	UnknownUser
	// UnitFileMissing — nothing at ~/.config/systemd/user/statbus-upgrade@.service.
	// This is the demo case: the box cannot follow its channel at all.
	UnitFileMissing
	// UnitFileDrifted — present but not byte-identical to the repo template.
	// The box runs an old unit: stale WatchdogSec/TimeoutStartSec keep applying
	// forever because nothing ever rewrites them.
	UnitFileDrifted
	// Inactive — unit file correct, but the instance is not running. The box
	// will not tick, so it will not discover, so the page goes stale silently.
	Inactive
)

func (s State) String() string {
	switch s {
	case OK:
		return "ok"
	case NotApplicable:
		return "not-applicable"
	case UnknownUser:
		return "unknown-user"
	case UnitFileMissing:
		return "unit-file-missing"
	case UnitFileDrifted:
		return "unit-file-drifted"
	case Inactive:
		return "inactive"
	}
	return "unknown"
}

// Report is one inspection's result. It carries the paths and instance name so
// the announce can be specific — an operator should never have to go and find
// out WHICH file or WHICH unit we mean.
type Report struct {
	State    State
	Instance string // e.g. statbus-upgrade@statbus_dev.service ("" when underivable)
	UnitPath string // where the user unit belongs
	RepoPath string // the template it must match
}

// Healthy reports whether the box meets its floor. NotApplicable and
// UnknownUser count as healthy: neither is evidence of a breach, and turning
// "cannot tell" into an alarm is how alarms get ignored.
func (r Report) Healthy() bool {
	return r.State == OK || r.State == NotApplicable || r.State == UnknownUser
}

// Announce is the loud, un-ignorable message for a box below its floor. It
// states what is wrong, what it COSTS (the part the demo incident proves people
// need — a missing unit reads as harmless until you know it means nine days of
// silent staleness), and the one command that fixes it.
//
// Returns "" when healthy: callers can print unconditionally without guarding.
func (r Report) Announce() string {
	if r.Healthy() {
		return ""
	}
	var b strings.Builder
	b.WriteString("╔══ AUTOMATIC UPDATE CHECKS NEED REPAIR ══\n")
	switch r.State {
	case UnitFileMissing:
		b.WriteString("║ Automatic update checks are not installed.\n")
		b.WriteString("║ This StatBus installation will not discover new releases until repaired.\n")
	case UnitFileDrifted:
		b.WriteString("║ Automatic update settings are out of date.\n")
		b.WriteString("║ Repair them so future release checks use the supported settings.\n")
	case Inactive:
		b.WriteString("║ Automatic update checks are not running.\n")
		b.WriteString("║ This StatBus installation will not discover new releases until repaired.\n")
	}
	b.WriteString("║\n")
	b.WriteString("║ FIX — run:\n")
	b.WriteString("║     curl -fsSL https://statbus.org/install.sh | bash\n")
	b.WriteString("╚════════════════════════════════════════════════")
	return b.String()
}

// runner is the systemd probe, injected so the decision logic is testable
// without a live systemd. Production passes isActiveSystemd.
type runner func(instance string) bool

// Inspect compares the floor against reality. dir is the project directory.
func Inspect(dir string) Report {
	return inspectWith(dir, os.Getenv("USER"), runtime.GOOS, isActiveSystemd)
}

func inspectWith(dir, user, goos string, isActive runner) Report {
	r := Report{
		UnitPath: UserUnitPath(),
		RepoPath: filepath.Join(dir, "ops", "statbus-upgrade.service"),
	}
	if goos != "linux" {
		r.State = NotApplicable
		return r
	}
	if user == "" {
		r.State = UnknownUser
		return r
	}
	r.Instance = fmt.Sprintf("statbus-upgrade@%s.service", user)

	switch fileCheck(dir) {
	case fileMissing:
		r.State = UnitFileMissing
		return r
	case fileDrifted:
		r.State = UnitFileDrifted
		return r
	}
	if !isActive(r.Instance) {
		r.State = Inactive
		return r
	}
	r.State = OK
	return r
}

// fileVerdict is the OS-INDEPENDENT half: what the bytes on disk say, with no
// reference to systemd, the platform, or whether anything is running.
type fileVerdict int

const (
	fileOK fileVerdict = iota
	fileMissing
	fileDrifted
	// fileNoTemplate — no repo template to compare against. Not a breach: we
	// cannot assert drift without a reference, and manufacturing an alarm from a
	// missing source file would corrode the surface whose credibility is the
	// whole point.
	fileNoTemplate
)

func fileCheck(dir string) fileVerdict {
	repo, err := os.ReadFile(filepath.Join(dir, "ops", "statbus-upgrade.service"))
	if err != nil {
		return fileNoTemplate
	}
	onDisk, err := os.ReadFile(UserUnitPath())
	if err != nil {
		return fileMissing
	}
	if !bytes.Equal(repo, onDisk) {
		return fileDrifted
	}
	return fileOK
}

// FileMatchesRepo reports whether the on-disk user unit is byte-identical to
// the repo template.
//
// DELIBERATELY OS-INDEPENDENT, and that is load-bearing rather than incidental.
// This is the install ladder's drift gate (cmd.unitFileMatchesRepo delegates
// here), and it is the pure, unit-testable seam its tests exercise on a
// developer's macOS laptop. Routing it through Inspect instead would make it
// answer "matches" on any non-Linux host via the NotApplicable gate — which is
// exactly the regression cli/cmd/unit_reconcile_test.go caught when this
// package was first wired in. The OS gate belongs to the ANNOUNCE (don't alarm
// a laptop), never to the byte compare.
func FileMatchesRepo(dir string) bool {
	switch fileCheck(dir) {
	case fileMissing, fileDrifted:
		return false
	default:
		return true
	}
}

// UserUnitPath is the install destination for the user-level upgrade unit. The
// unit is copied here verbatim (the %h/%i/%u specifiers resolve at systemd
// runtime, not at copy time), which is why a byte-compare is the exact drift
// check.
func UserUnitPath() string {
	return filepath.Join(os.Getenv("HOME"), ".config", "systemd", "user", "statbus-upgrade@.service")
}

func isActiveSystemd(instance string) bool {
	out, err := exec.Command("systemctl", "--user", "is-active", instance).Output()
	return systemdActivityIsRunning(string(out), err)
}

func systemdActivityIsRunning(output string, err error) bool {
	state := strings.TrimSpace(output)
	return err == nil || state == "active" || state == "activating"
}
