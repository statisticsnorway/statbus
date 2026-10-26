package cmd

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
)

// runningDaemon is what the box shows about the resident upgrader: whether
// its unit is active, and the program its main process is executing.
// exeDeleted is true when that program's file was replaced or removed on disk
// after the upgrader started, which Linux reports as "(deleted)" on
// /proc/<pid>/exe.
type runningDaemon struct {
	active     bool
	exe        string
	exeDeleted bool
}

// staleDaemonFinalAction is the STATBUS-382 decision: an active upgrader
// that is not running the ./sb this install leaves on disk is restarted at
// install exit, so its next claim runs the installed code. The upgrader keeps
// the program it loaded; replacing ./sb underneath it is invisible to it, and
// a stale upgrader applies its old logic to a newer checkout (Norway 2026-09-22:
// an rc.18 daemon on an rc.20 box). Inside the upgrader's own post-upgrade
// fixup the exit-42/unit handoff restarts it, so nothing is queued here.
func staleDaemonFinalAction(d runningDaemon, diskSB string, postUpgradeFixup bool) (upgradeDaemonFinalAction, string) {
	if !d.active || postUpgradeFixup {
		return upgradeDaemonNoAction, ""
	}
	if d.exeDeleted {
		return upgradeDaemonRestart, "is running a program that was replaced on disk"
	}
	same, err := sameFileContent(d.exe, diskSB)
	if err != nil || !same {
		return upgradeDaemonRestart, "is running a different program than " + diskSB
	}
	return upgradeDaemonNoAction, ""
}

func sameFileContent(a, b string) (bool, error) {
	ab, err := os.ReadFile(a)
	if err != nil {
		return false, err
	}
	bb, err := os.ReadFile(b)
	if err != nil {
		return false, err
	}
	return bytes.Equal(ab, bb), nil
}

// observeRunningDaemon reads the resident upgrader's unit state and main
// process executable. It is a thin adapter over the shared observeUpgrader
// (upgrader.go) — the same observation `sb upgrader status` renders — so
// install's stale-daemon decision and the status command can never disagree.
// Off Linux, or when the unit or its process cannot be seen, it reports an
// inactive daemon: there is nothing to restart.
var observeRunningDaemon = func(dir string) runningDaemon {
	obs := observeUpgrader(dir)
	if obs.activeState != "active" || obs.mainPID == 0 || obs.exeTarget == "" {
		// Not running, or the main process's executable could not be read:
		// nothing to restart (preserved observeRunningDaemon semantics).
		return runningDaemon{}
	}
	return runningDaemon{
		active:     true,
		exe:        obs.exeLink,
		exeDeleted: obs.exeDeleted,
	}
}

// queueStaleDaemonRestart applies staleDaemonFinalAction to the resident
// upgrader at install exit and says why when it queues a restart.
func queueStaleDaemonRestart(dir string, action *upgradeDaemonFinalAction) {
	next, why := staleDaemonFinalAction(observeRunningDaemon(dir), filepath.Join(dir, "sb"), postUpgradeFixup || os.Getenv("STATBUS_POST_UPGRADE_FIXUP") == "1")
	if next == upgradeDaemonNoAction {
		return
	}
	fmt.Printf("  The upgrader %s; restart queued for install exit\n", why)
	*action = mergeUpgradeDaemonFinalAction(*action, next)
}
