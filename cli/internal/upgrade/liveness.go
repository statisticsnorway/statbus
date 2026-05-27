package upgrade

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Liveness backstop (plan upgrade-resume-structural-whole.md piece #7,
// LOAD-BEARING). An external sidecar timer (statbus-upgrade-liveness@.timer,
// OnUnitActiveSec=5m) runs `sb upgrade liveness-check`, whose pure core is
// livenessDecision below. It is the universal backstop that converts a SLOW
// upgrade LOOP — a hung-migrate (#3 bounds each cycle at 30m) or hung-reconnect
// (connect() bounds each cycle at 5m) that keeps restarting, each individual
// cycle under its own bound so it never trips — into a terminal TRIP once the
// upgrade unit has been NOT-healthy-stable for a cumulative N (=30m).
//
// Why an EXTERNAL observer with its OWN persisted clock, not the existing
// signals (architect-settled):
//   - heartbeat-staleness can't see a LOOP: a slow loop rewrites a fresh
//     heartbeat every ~2.5m cycle → always looks alive.
//   - NRestarts undercounts: the exit-42 self-update restart is
//     SuccessExitStatus + RestartForceExitStatus → systemd doesn't count it.
//   - the in-loop SERVICE_STUCK_RETRY_LOOP markTerminal runs POST-READY, so a
//     loop that dies BEFORE READY=1 (the NO/rune TimeoutStartSec case) never
//     reaches it.
// So the observer persists last_healthy_at in an OWN state file
// (tmp/upgrade-liveness-state) that survives the upgrade unit's restarts, and
// trips on cumulative not-healthy time — the only thing that distinguishes a
// slow loop from a healthy box.

// livenessStallThreshold (N) is how long the upgrade unit may be NOT
// healthy-stable before the liveness observer trips it. 30m clears the legit
// "DB restarted during maintenance, a few quick retries" transient (the upgrade
// unit's own comment cites ~3 retries) by a wide margin, and matches the #3
// per-cycle worst-case bound (a hung migrate is killed at its 30m
// runCommandToLog timeout), so worst-case first-hang→failed ≈ 30m either way.
const livenessStallThreshold = 30 * time.Minute

// livenessStableFor is how long the upgrade unit must have been
// active+running before it counts as healthy-STABLE. Clears the mid-loop
// transient where a restarting unit briefly shows active+running between
// failures. 2m > a single restart cycle's active window.
const livenessStableFor = 2 * time.Minute

// unitStatus is the parsed `systemctl --user show statbus-upgrade@<u>` output
// the observer consults.
type unitStatus struct {
	ActiveState string    // active | activating | failed | inactive | ...
	SubState    string    // running | start | failed | ...
	ActiveEnter time.Time // ActiveEnterTimestamp — when the unit last entered its current ActiveState
}

// livenessState is the OBSERVER-OWNED persisted anchor (JSON in
// tmp/upgrade-liveness-state). It survives the upgrade unit's restarts — that
// persistence is the whole point (cumulative-activating can't be derived from
// the unit's own volatile NRestarts/ActiveEnterTimestamp).
type livenessState struct {
	LastHealthyAt time.Time `json:"last_healthy_at"`
}

// livenessInput bundles everything livenessDecision needs (all gathered by the
// I/O wrapper: systemctl show, the persisted state, a DB probe, the sentinel).
type livenessInput struct {
	unit            unitStatus
	dbReachable     bool          // could we query public.upgrade?
	stuckInProgress int           // count of public.upgrade rows in state='in_progress' (0 when none / unknown)
	state           livenessState // persisted last_healthy_at
	tripped         bool          // tmp/upgrade-liveness-tripped sentinel present?
}

type livenessActionKind int

const (
	livenessWait    livenessActionKind = iota // within N, or already tripped — no-op this tick
	livenessHealthy                           // healthy-stable — record last_healthy_at (+ clear sentinel)
	livenessTrip                              // NOT healthy-stable for > N — stop unit + notify + sentinel
)

func (k livenessActionKind) String() string {
	switch k {
	case livenessHealthy:
		return "healthy"
	case livenessTrip:
		return "trip"
	default:
		return "wait"
	}
}

// livenessAction is what the I/O wrapper must do after a decision.
type livenessAction struct {
	kind          livenessActionKind
	clearSentinel bool // on healthy: remove a stale tripped sentinel (the unit recovered)
}

// isHealthyStable reports whether the upgrade unit is genuinely healthy: the
// process is active+running, has been so longer than livenessStableFor (not a
// mid-loop blip), AND — if we can see the DB — no public.upgrade row is wedged
// in_progress. If the DB is unreachable we cannot CONFIRM clean, so it is not
// "stable" (but DB-unreachable alone doesn't trip — see livenessDecision: the
// staleness timer is the arbiter).
func (in livenessInput) isHealthyStable(now time.Time) bool {
	if in.unit.ActiveState != "active" || in.unit.SubState != "running" {
		return false
	}
	if now.Sub(in.unit.ActiveEnter) < livenessStableFor {
		return false // just (re)entered active — could be a mid-loop transient
	}
	if !in.dbReachable {
		return false // can't confirm no wedged upgrade
	}
	if in.stuckInProgress > 0 {
		return false // an upgrade row is wedged even if the process looks up
	}
	return true
}

// livenessDecision is the pure backstop logic. now is injected for tests.
//
//   - healthy-stable                       → livenessHealthy (record last_healthy_at; clear sentinel)
//   - already tripped (sentinel present)   → livenessWait    (dedup: notify+stop happen ONCE)
//   - not healthy-stable, stale > N         → livenessTrip
//   - otherwise (not healthy, within N)    → livenessWait    (legit transient — no false trip)
//
// A zero-value state.LastHealthyAt (fresh box / first run) is treated by the
// caller as "seed to now" BEFORE calling, so a brand-new install never trips;
// here a zero LastHealthyAt with a not-healthy unit would compute a huge
// staleness, so the caller MUST seed. (Documented contract; the wrapper seeds.)
func livenessDecision(now time.Time, in livenessInput, n time.Duration) (livenessAction, livenessState) {
	if in.isHealthyStable(now) {
		return livenessAction{kind: livenessHealthy, clearSentinel: in.tripped}, livenessState{LastHealthyAt: now}
	}
	// Not healthy-stable.
	if in.tripped {
		return livenessAction{kind: livenessWait}, in.state // already handled; dedup
	}
	if now.Sub(in.state.LastHealthyAt) > n {
		return livenessAction{kind: livenessTrip}, in.state
	}
	return livenessAction{kind: livenessWait}, in.state
}

// --- I/O layer (paths + systemctl + state file + orchestrator) ---

func livenessStatePath(projDir string) string {
	return filepath.Join(projDir, "tmp", "upgrade-liveness-state")
}

func livenessTrippedSentinelPath(projDir string) string {
	return filepath.Join(projDir, "tmp", "upgrade-liveness-tripped")
}

// readLivenessState loads the observer's persisted anchor. A missing/corrupt
// file returns ok=false so the caller seeds last_healthy_at=now (a fresh box or
// first run must never trip).
func readLivenessState(projDir string) (livenessState, bool) {
	data, err := os.ReadFile(livenessStatePath(projDir))
	if err != nil {
		return livenessState{}, false
	}
	var st livenessState
	if json.Unmarshal(data, &st) != nil || st.LastHealthyAt.IsZero() {
		return livenessState{}, false
	}
	return st, true
}

// writeLivenessState persists the anchor atomically (.tmp + rename) so a crash
// mid-write can't corrupt it. Best-effort: the caller logs on failure.
func writeLivenessState(projDir string, st livenessState) error {
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
		return err
	}
	data, err := json.Marshal(st)
	if err != nil {
		return err
	}
	p := livenessStatePath(projDir)
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

// parseUnitStatus parses the key=value lines of
// `systemctl --user show <unit> --property=ActiveState,SubState,ActiveEnterTimestamp`.
// ActiveEnterTimestamp is systemd's human format (e.g.
// "Tue 2026-05-27 21:30:00 UTC"); a missing/unparseable timestamp yields a zero
// ActiveEnter (treated as "just entered" → not-stable, the safe direction).
// Pure + unit-testable.
func parseUnitStatus(showOutput string) unitStatus {
	var u unitStatus
	for _, line := range strings.Split(showOutput, "\n") {
		k, v, found := strings.Cut(strings.TrimSpace(line), "=")
		if !found {
			continue
		}
		switch k {
		case "ActiveState":
			u.ActiveState = v
		case "SubState":
			u.SubState = v
		case "ActiveEnterTimestamp":
			u.ActiveEnter = parseSystemdTimestamp(v)
		}
	}
	return u
}

// parseSystemdTimestamp parses systemd's default timestamp rendering. systemd
// prints "Dow YYYY-MM-DD HH:MM:SS TZ" (e.g. "Tue 2026-05-27 21:30:00 UTC"); an
// empty value ("ActiveEnterTimestamp=") means the unit never entered active.
// Returns zero time on any parse failure (caller treats zero as not-stable).
func parseSystemdTimestamp(v string) time.Time {
	v = strings.TrimSpace(v)
	if v == "" {
		return time.Time{}
	}
	// Drop the leading day-of-week token ("Tue ") — Go's reference layout
	// doesn't round-trip systemd's abbreviated Dow cleanly across locales.
	if i := strings.IndexByte(v, ' '); i >= 0 {
		rest := strings.TrimSpace(v[i+1:])
		for _, layout := range []string{"2006-01-02 15:04:05 MST", "2006-01-02 15:04:05 -0700"} {
			if t, err := time.Parse(layout, rest); err == nil {
				return t
			}
		}
	}
	return time.Time{}
}

// queryStuckInProgress returns (count, reachable) of public.upgrade rows in
// state='in_progress'. Reachable=false when the DB can't be queried (the
// caller treats not-reachable as not-healthy-stable but does NOT trip on it
// alone — the staleness timer is the arbiter).
func (d *Service) queryStuckInProgress(ctx context.Context) (int, bool) {
	if d.queryConn == nil {
		return 0, false
	}
	var n int
	qctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := d.queryConn.QueryRow(qctx,
		"SELECT count(*) FROM public.upgrade WHERE state = 'in_progress'").Scan(&n); err != nil {
		return 0, false
	}
	return n, true
}

// RunLivenessCheck is the `sb upgrade liveness-check` entrypoint (run by the
// statbus-upgrade-liveness@.timer every 5m). It gathers the unit status, the
// persisted anchor, a DB probe, and the sentinel; runs livenessDecision; and
// executes the action. Idempotent + dedup'd via the sentinel: a TRIP fires the
// stop+notify ONCE, subsequent ticks no-op while the sentinel is present.
//
// dbConnected must already be done by the caller (LoadConfigAndConnect) when
// possible; if d.queryConn is nil the DB probe reports unreachable.
func (d *Service) RunLivenessCheck(ctx context.Context) error {
	now := time.Now()
	instance := livenessTargetInstance()
	if instance == "" {
		return fmt.Errorf("liveness-check: cannot determine upgrade unit instance (USER unset)")
	}

	// systemctl show the upgrade unit (NOT the liveness unit — we observe the
	// upgrade service's health).
	out, _ := exec.Command("systemctl", "--user", "show", instance,
		"--property=ActiveState", "--property=SubState", "--property=ActiveEnterTimestamp").Output()
	unit := parseUnitStatus(string(out))

	stuck, dbReachable := d.queryStuckInProgress(ctx)

	st, ok := readLivenessState(d.projDir)
	if !ok {
		// Fresh box / first run / corrupt: seed to now so we never trip a
		// brand-new install, then return — next tick evaluates against a real
		// baseline.
		st = livenessState{LastHealthyAt: now}
		if err := writeLivenessState(d.projDir, st); err != nil {
			fmt.Printf("liveness-check: seed state write failed: %v\n", err)
		}
		fmt.Printf("liveness-check: seeded last_healthy_at=%s (first run)\n", now.Format(time.RFC3339))
		return nil
	}

	_, tripErr := os.Stat(livenessTrippedSentinelPath(d.projDir))
	tripped := tripErr == nil

	in := livenessInput{unit: unit, dbReachable: dbReachable, stuckInProgress: stuck, state: st, tripped: tripped}
	act, newState := livenessDecision(now, in, livenessStallThreshold)

	switch act.kind {
	case livenessHealthy:
		if err := writeLivenessState(d.projDir, newState); err != nil {
			fmt.Printf("liveness-check: state write failed: %v\n", err)
		}
		if act.clearSentinel {
			os.Remove(livenessTrippedSentinelPath(d.projDir)) // re-arm: a future loop can trip again
			fmt.Println("liveness-check: upgrade unit recovered — cleared tripped sentinel")
		}
	case livenessTrip:
		d.tripLiveness(ctx, instance, now.Sub(st.LastHealthyAt))
	case livenessWait:
		// no-op (within N, or already tripped)
	}
	return nil
}

// livenessTargetInstance returns the upgrade unit instance the observer watches,
// e.g. "statbus-upgrade@statbus_dev.service". Mirrors install.go's
// serviceInstance (@%i==%u == the deployment user).
func livenessTargetInstance() string {
	u := os.Getenv("USER")
	if u == "" {
		return ""
	}
	return fmt.Sprintf("statbus-upgrade@%s.service", u)
}

// tripLiveness halts a wedged slow upgrade LOOP: stop the upgrade unit, mark any
// stuck row failed (clean thin DB call — the observer has DB access), fire the
// LOUD Slack callback (REQUIRED: unattended deployments are monitored via Slack,
// not by watching the unit), and write the dedup sentinel so the stop+notify
// happen exactly ONCE. Operator recovery is `./sb install`.
func (d *Service) tripLiveness(ctx context.Context, instance string, staleFor time.Duration) {
	reason := fmt.Sprintf("liveness: upgrade unit not healthy-stable for %s (> %s) — slow upgrade loop; halting",
		staleFor.Truncate(time.Minute), livenessStallThreshold)
	fmt.Printf("LIVENESS_TRIP: %s\n", reason)

	// 1. Stop the looping upgrade unit (halt the loop). Best-effort.
	if err := exec.Command("systemctl", "--user", "stop", instance).Run(); err != nil {
		fmt.Printf("liveness-check: stop %s failed: %v\n", instance, err)
	}

	// 2. Mark a wedged row failed so the app's upgrade UI unblocks immediately.
	// Clean thin call; ./sb install's RecoverFromFlag is the backstop if this
	// can't land. Scoped to in_progress so we never clobber a completed row.
	if d.queryConn != nil {
		qctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		if _, err := d.queryConn.Exec(qctx,
			"UPDATE public.upgrade SET state = 'failed', error = $1 WHERE state = 'in_progress'",
			reason); err != nil {
			fmt.Printf("liveness-check: mark in_progress rows failed: %v (./sb install will reconcile)\n", err)
		}
		cancel()
	}

	// 3. LOUD Slack notification (required for unattended monitoring).
	d.runCallback("liveness-trip", map[string]string{
		"STATBUS_LIVENESS_TRIPPED": "1",
		"STATBUS_LIVENESS_REASON":  reason,
	})

	// 4. Dedup sentinel: subsequent 5-min ticks no-op while present; cleared
	// when the unit recovers (livenessHealthy → clearSentinel) or by ./sb install.
	if err := os.WriteFile(livenessTrippedSentinelPath(d.projDir), []byte(reason+"\n"), 0644); err != nil {
		fmt.Printf("liveness-check: write tripped sentinel failed: %v\n", err)
	}
}
