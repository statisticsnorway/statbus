package cmd

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// runningDaemon is what the box shows about the resident upgrade daemon: whether
// its unit is active, and the program its main process is executing.
// exeDeleted is true when that program's file was replaced or removed on disk
// after the daemon started, which Linux reports as "(deleted)" on
// /proc/<pid>/exe.
type runningDaemon struct {
	active     bool
	exe        string
	exeDeleted bool
}

// staleDaemonFinalAction is the STATBUS-382 decision: an active upgrade daemon
// that is not running the ./sb this install leaves on disk is restarted at
// install exit, so its next claim runs the installed code. A daemon keeps the
// program it loaded; replacing ./sb underneath it is invisible to it, and a
// stale daemon applies its old logic to a newer checkout (Norway 2026-09-22:
// an rc.18 daemon on an rc.20 box). Inside the daemon's own post-upgrade fixup
// the parent's exit-42 handoff restarts it, so nothing is queued here.
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

// observeRunningDaemon reads the resident upgrade daemon's unit state and main
// process executable from systemd and /proc. Off Linux, or when the unit or
// its process cannot be seen, it reports an inactive daemon: there is nothing
// to restart.
var observeRunningDaemon = func(dir string) runningDaemon {
	if runtime.GOOS != "linux" {
		return runningDaemon{}
	}
	instance := serviceInstance(dir)
	if instance == "" {
		return runningDaemon{}
	}
	if exec.Command("systemctl", "--user", "is-active", "--quiet", instance).Run() != nil {
		return runningDaemon{}
	}
	out, err := exec.Command("systemctl", "--user", "show", instance, "-p", "MainPID", "--value").Output()
	pid := strings.TrimSpace(string(out))
	if err != nil || pid == "" || pid == "0" {
		return runningDaemon{}
	}
	procExe := filepath.Join("/proc", pid, "exe")
	target, err := os.Readlink(procExe)
	if err != nil {
		return runningDaemon{}
	}
	return runningDaemon{
		active:     true,
		exe:        procExe,
		exeDeleted: strings.HasSuffix(target, " (deleted)"),
	}
}

// queueStaleDaemonRestart applies staleDaemonFinalAction to the resident
// daemon at install exit and says why when it queues a restart.
func queueStaleDaemonRestart(dir string, action *upgradeDaemonFinalAction) {
	next, why := staleDaemonFinalAction(observeRunningDaemon(dir), filepath.Join(dir, "sb"), postUpgradeFixup || os.Getenv("STATBUS_POST_UPGRADE_FIXUP") == "1")
	if next == upgradeDaemonNoAction {
		return
	}
	fmt.Printf("  The upgrade service %s; restart queued for install exit\n", why)
	*action = mergeUpgradeDaemonFinalAction(*action, next)
}
