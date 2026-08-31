package upgrade

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
)

// Keys STATBUS-308 writes into public.system_info. Named here rather than
// spelled at each call site so the writers and the admin UI cannot drift.
const (
	UnitFloorStateKey    = "unit_floor_state"
	UnitFloorDetailKey   = "unit_floor_detail"
	UnitFloorIntervalKey = "unit_floor_poll_interval_seconds"
)

// DefaultPollInterval is the service's poll cadence when UPGRADE_CHECK_INTERVAL
// is unset or unparseable. Defined once because two consumers must agree on it:
// loadConfig's fallback, and the install verb, which writes it as the yardstick
// the admin UI measures staleness against on a box whose service has not yet
// ticked. A second literal here would let the yardstick drift from the cadence
// it is supposed to describe.
const DefaultPollInterval = 6 * time.Hour

// StampUnitFloor records the observed floor state in public.system_info so the
// admin UI can show it (STATBUS-308).
//
// WHY THE DATABASE AND NOT A FUNCTION OR VIEW. The floor is live systemd
// reality: a unit file under ~/.config/systemd/user and `systemctl --user
// is-active`. Postgres and the app both run in CONTAINERS and can see neither.
// No database-side construct can observe this state, so a host-side process must
// push it in. That is the whole reason this is a write rather than a query.
//
// THE TIMESTAMP IS THE POINT, not a detail. The headline case is the unit
// MISSING — no service running — and a service that does not exist cannot report
// its own absence. So this is called on EVERY tick, not only when the state
// changes: a healthy box refreshes the row continuously, and a box whose service
// is gone stops. system_info.updated_at going stale is then not missing data, it
// IS the report that nothing is checking. That is the only shape that can report
// the absence of the reporter without inventing a second watchdog to watch the
// first.
//
// The poll interval is written alongside so the reader derives its staleness
// threshold as a MULTIPLE OF THE ACTUAL CADENCE rather than hardcoding minutes.
// If the interval ever changes, the warning moves with it; a threshold that
// silently stops matching the thing it measures is its own defect.
//
// Best-effort. A failed stamp affects a UI banner, never the upgrade — the
// journal announce is the primary record and does not depend on the database.
func StampUnitFloor(ctx context.Context, conn *pgx.Conn, projDir string, interval time.Duration) {
	if conn == nil {
		return // no live connection (e.g. before the DB is up at service start)
	}
	r := unitfloor.Inspect(projDir)

	detail := r.Instance
	if !r.Healthy() {
		detail = fmt.Sprintf("%s (unit file: %s)", r.Instance, r.UnitPath)
	}

	_, err := conn.Exec(ctx,
		`INSERT INTO public.system_info (key, value) VALUES
		     ($1, $2),
		     ($3, $4),
		     ($5, $6)
		 ON CONFLICT (key) DO UPDATE SET
		     value = EXCLUDED.value,
		     updated_at = clock_timestamp()`,
		UnitFloorStateKey, r.State.String(),
		UnitFloorDetailKey, detail,
		UnitFloorIntervalKey, fmt.Sprintf("%d", int(interval.Seconds())),
	)
	if err != nil {
		log.Printf("StampUnitFloor: upsert failed (non-fatal; the journal announce is unaffected): %v", err)
	}
}

// announceUnitFloor writes a floor breach to the journal (STATBUS-308).
//
// WHAT THIS CAN AND CANNOT SEE. A running service cannot report its own
// absence, so the headline case — the unit missing entirely, which is what left
// demo silent for nine days — is covered by the operator verbs, not here. What
// this catches is the box that IS running but is running the wrong thing: a
// unit file that has drifted from the shipped template, so its watchdog and
// timeout settings are frozen at whatever they were on install day. That state
// is invisible today and stays invisible forever, because nothing rewrites a
// unit that nobody knows is stale.
//
// Both surfaces call unitfloor.Inspect, so the service and the CLI cannot come
// to different conclusions about what "correct" means.
//
// Detection only. No unit writes, no self-restart, no reconcile — the repair is
// `./sb install`, run by a human, per the no-standing-self-heal rule.
func (d *Service) announceUnitFloor() {
	r := unitfloor.Inspect(d.projDir)
	d.lastUnitFloorState = r.State
	if msg := r.Announce(); msg != "" {
		log.Printf("unit floor breach (%s):\n%s", r.State, msg)
	}
}

// announceUnitFloorIfChanged re-checks on a tick and journals ONLY on a
// transition.
//
// Deliberately not every tick. A line repeated each minute forever is read once
// and filtered out thereafter — that is how a real alert becomes background
// noise, and this ticket exists precisely because a signal was not noticed. A
// transition is the event worth recording: the moment a box drops below its
// floor, and the moment someone repairs it (worth journaling too, so the fix is
// visible in the same place as the complaint).
func (d *Service) announceUnitFloorIfChanged() {
	r := unitfloor.Inspect(d.projDir)
	if r.State == d.lastUnitFloorState {
		return
	}
	prev := d.lastUnitFloorState
	d.lastUnitFloorState = r.State
	if msg := r.Announce(); msg != "" {
		log.Printf("unit floor breach (%s, was %s):\n%s", r.State, prev, msg)
		return
	}
	log.Printf("unit floor restored: %s (was %s)", r.State, prev)
}
