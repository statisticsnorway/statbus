package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"testing"
)

// STATBUS-055 — the migrate advisory-lock orphan gate. classifyAdvisoryHolder is
// the shared detection used by BOTH the gate (checkSessionsClean) and the action
// (cleanOrphanSessions Phase 2). These Docker-free tests are the primary guard
// for the gap: a tagged DEAD-PID holder must be flagged (the case the old gate
// missed), a tagged LIVE-PID holder must be left alone (a healthy migration
// idling between statements — killing it would abort a real migration).
func TestClassifyAdvisoryHolder(t *testing.T) {
	alive := func(int) bool { return true }
	dead := func(int) bool { return false }

	cases := []struct {
		name       string
		appName    string
		pidAlive   func(int) bool
		wantZombie bool
	}{
		{"empty app is an unidentified zombie", "", dead, true},
		{"tagged dead-PID holder is a zombie (the STATBUS-055 gap)", "statbus-migrate-99999", dead, true},
		{"tagged live-PID holder is a healthy migration — leave alone", "statbus-migrate-4242", alive, false},
		{"subprocess sql tag is malformed as a holder — leave alone", "statbus-migrate-sql-4242", dead, false},
		{"non-numeric migrate tag is malformed — leave alone", "statbus-migrate-notapid", dead, false},
		{"worker is legitimate even with a dead probe", "worker", dead, false},
		{"live operator psql is legitimate", "psql", dead, false},
		{"PostgREST pool is legitimate", "PostgREST", dead, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			gotZombie, reason := classifyAdvisoryHolder(c.appName, c.pidAlive)
			if gotZombie != c.wantZombie {
				t.Errorf("classifyAdvisoryHolder(%q) zombie=%v, want %v (reason: %s)", c.appName, gotZombie, c.wantZombie, reason)
			}
			if reason == "" {
				t.Errorf("classifyAdvisoryHolder(%q) must always give a reason", c.appName)
			}
		})
	}
}

// procAlive backs the real PID-liveness probe. The gate must never kill a live
// migration's lock, and must recognise a dead owner.
func TestProcAlive(t *testing.T) {
	if !procAlive(os.Getpid()) {
		t.Error("procAlive(own PID) must be true — killing a live migration's lock would abort it")
	}
	// A guaranteed-dead PID: spawn a trivial child, wait for it to exit + be
	// reaped, then its PID is gone → syscall.Kill(pid, 0) → ESRCH.
	child := exec.Command("true")
	if err := child.Start(); err != nil {
		t.Skipf("cannot spawn a child to obtain a dead PID: %v", err)
	}
	pid := child.Process.Pid
	_ = child.Wait() // reap it → the PID is now dead
	if procAlive(pid) {
		t.Errorf("procAlive(reaped child PID %d) must be false — a dead migrate owner is a zombie", pid)
	}
}

// End-to-end of the pure detection: a mixed holder set yields exactly the zombie
// subset the gate flags and Phase 2 kills.
func TestClassifyAdvisoryHolder_MixedSet(t *testing.T) {
	self := os.Getpid()
	holders := []string{"", fmt.Sprintf("statbus-migrate-%d", self), "statbus-migrate-99999", "worker"}
	var zombies int
	for _, app := range holders {
		if z, _ := classifyAdvisoryHolder(app, procAlive); z {
			zombies++
		}
	}
	// empty + dead-99999 are zombies; self (alive) + worker are not.
	if zombies != 2 {
		t.Errorf("mixed holder set: got %d zombies, want 2 (empty + dead-PID)", zombies)
	}
}
