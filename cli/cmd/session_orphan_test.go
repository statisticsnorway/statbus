package cmd

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
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

// STATBUS-139 — the sessions verdict tri-state (defect 1: verdict-role conflation).
// classifySessions is the PURE mapping: a probe error is UNVERIFIABLE (retry), never
// a false dirty; a clean read needs BOTH zero leaked and zero zombies; otherwise
// verified DIRTY with counts. This is the check that stops a probe which merely
// couldn't get a connection slot from becoming a hard 'still saturated' verdict.
func TestClassifySessions(t *testing.T) {
	z := []zombieHolder{{BackendPID: 4242, AppName: "", Reason: "empty"}}
	cases := []struct {
		name     string
		leaked   int
		zombies  []zombieHolder
		probeErr error
		want     sessionsVerdictKind
	}{
		{"clean — nothing observed", 0, nil, nil, sessionsClean},
		{"dirty — leaked backends", 2, nil, nil, sessionsDirty},
		{"dirty — zombie holders", 0, z, nil, sessionsDirty},
		{"dirty — both", 3, z, nil, sessionsDirty},
		{"unverifiable — probe error, no counts", 0, nil, errors.New("db unreachable"), sessionsUnverifiable},
		// A probe error DOMINATES: even if stale counts were passed, a failed probe
		// must NEVER be reported as verified-dirty (would hard-fail on unverifiable).
		{"unverifiable dominates any counts", 5, z, errors.New("docker exec failed"), sessionsUnverifiable},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := classifySessions(c.leaked, c.zombies, c.probeErr)
			if got.kind != c.want {
				t.Fatalf("classifySessions(%d, %v, %v).kind = %v, want %v", c.leaked, c.zombies, c.probeErr, got.kind, c.want)
			}
			// The clean/dirty verdicts must NOT carry a probe error; unverifiable MUST.
			if (got.kind == sessionsUnverifiable) != (got.probeErr != nil) {
				t.Errorf("probeErr presence must match unverifiable: kind=%v probeErr=%v", got.kind, got.probeErr)
			}
		})
	}
}

// STATBUS-139 (d) — the failure message names WHAT was observed, so 'draining' and
// 'wedged' are distinguishable and the operator has an actionable evidence trail.
func TestSessionsVerdictDescribe(t *testing.T) {
	clean := classifySessions(0, nil, nil).describe()
	if !strings.Contains(clean, "clean") {
		t.Errorf("clean describe must say clean; got %q", clean)
	}

	dirty := classifySessions(2, []zombieHolder{{BackendPID: 1717}, {BackendPID: 2828}}, nil).describe()
	for _, want := range []string{"2 leaked", "1717", "2828"} {
		if !strings.Contains(dirty, want) {
			t.Errorf("dirty describe must name the evidence %q; got %q", want, dirty)
		}
	}

	unv := classifySessions(0, nil, errors.New("pool wedged: connection refused")).describe()
	for _, want := range []string{"could not be verified", "connection refused"} {
		if !strings.Contains(unv, want) {
			t.Errorf("unverifiable describe must name the probe error %q; got %q", want, unv)
		}
	}
}
