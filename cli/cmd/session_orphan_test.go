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
		// STATBUS-149 — the upgrade daemon's own advisory-lock connection, tagged
		// 'statbus-upgrade-daemon-<pid>' (service.go recoveryDSN). A live daemon
		// must be left alone (killing it was the self-regenerating "zombie" bug);
		// a dead-PID daemon tag is a genuine leftover to reap.
		{"live upgrade daemon holds its own lock — leave alone (STATBUS-149)", "statbus-upgrade-daemon-4242", alive, false},
		{"dead-PID upgrade-daemon tag is a zombie (STATBUS-149)", "statbus-upgrade-daemon-99999", dead, true},
		{"malformed upgrade-daemon tag — leave alone", "statbus-upgrade-daemon-notapid", dead, false},
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

// STATBUS-149 — the settle loop's kill-in-loop bound. A zombie reappearing
// after being killed (the 173→312→442 escalation the investigation found)
// must eventually FAIL LOUDLY, not be re-killed forever — settleLoopMayKillAgain
// is the pure gate that decides "another attempt is allowed" vs "the bound is
// exhausted". Pins the exact boundary: allowed for every attempt strictly
// below the max, refused AT the max (the N+1th attempt is where it trips).
func TestSettleLoopMayKillAgain(t *testing.T) {
	const max = sessionsSettleMaxKillAttempts // 5
	cases := []struct {
		attemptsSoFar int
		want          bool
	}{
		{0, true},        // first kill ever attempted — always allowed
		{1, true},
		{max - 1, true},  // the Nth attempt (still under the bound)
		{max, false},     // the (N+1)th attempt — bound trips here
		{max + 1, false}, // already over — stays refused
	}
	for _, c := range cases {
		if got := settleLoopMayKillAgain(c.attemptsSoFar, max); got != c.want {
			t.Errorf("settleLoopMayKillAgain(%d, %d) = %v, want %v", c.attemptsSoFar, max, got, c.want)
		}
	}
}

// A zombie appearing mid-window (not present on the first probe, only later)
// is indistinguishable to the bound check from one present from the start —
// settleLoopMayKillAgain only counts ATTEMPTS MADE, never WHEN in the window
// they occurred. This is what lets a genuinely late-appearing zombie (like
// pid 442, which only showed up in the settle loop's own re-probe, never in
// Phase 2's initial snapshot) still get a kill attempt: the bound governs
// how many times we may act, not which iteration we're on.
func TestSettleLoopMayKillAgain_MidWindowZombieStillGetsAnAttempt(t *testing.T) {
	// Simulate: iterations 1-3 were clean (no kill attempted, killAttempts
	// stays 0), then a zombie appears on iteration 4 — it must still be
	// allowed a kill attempt, since killAttempts (0) is well under the bound.
	killAttempts := 0
	if !settleLoopMayKillAgain(killAttempts, sessionsSettleMaxKillAttempts) {
		t.Fatal("a zombie appearing after several clean iterations must still get a kill attempt (killAttempts is what's bounded, not elapsed iterations)")
	}
}

// STATBUS-149 — the regenerating-source failure message names the evidence
// (total killed, attempts made, the last observed verdict) an operator or the
// next investigation needs — never a bare "still saturated".
func TestRegeneratingZombieError(t *testing.T) {
	last := classifySessions(0, []zombieHolder{{BackendPID: 442, AppName: "", Reason: "empty application_name → unidentified zombie"}}, nil)
	err := regeneratingZombieError(3, 5, last)
	for _, want := range []string{"REGENERATING", "3 killed", "5 attempt", "442", "STATBUS-149"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("regeneratingZombieError message missing %q; got %q", want, err.Error())
		}
	}
}

// STATBUS-149 — the zero-zombie path stays a true no-op: terminateZombieAdvisoryHolders
// must return immediately without attempting any docker-exec call when there is
// nothing to kill (verified by the empty list short-circuiting before the
// exec.Command is ever constructed — no docker/DB access needed for this case,
// so it's safe to run as a plain unit test).
func TestTerminateZombieAdvisoryHolders_EmptyIsNoop(t *testing.T) {
	n, err := terminateZombieAdvisoryHolders("/nonexistent-dir-must-never-be-touched", "postgres", "statbus_local", nil)
	if err != nil {
		t.Fatalf("empty zombie list must be a no-op, got error: %v", err)
	}
	if n != 0 {
		t.Errorf("empty zombie list must kill 0, got %d", n)
	}
}
