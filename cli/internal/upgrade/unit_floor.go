package upgrade

import (
	"log"

	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
)

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
