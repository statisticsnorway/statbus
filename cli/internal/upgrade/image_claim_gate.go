package upgrade

import "time"

// STATBUS-046 slice 3c (architect-ruled) — the images-ready CLAIM GATE. Today
// both claim sites (executeScheduled, ExecuteUpgradeInline) consult only
// state+scheduled_at, never docker_images_status — so a mid-publication
// image-404 (CI still building, or CI failed) can reach the pull. This file
// holds the PURE gate decision (no I/O); service.go wires the persisted state
// (docker_images_status, scheduled_at) around it, mirroring the
// resumeEscalation/recovery_escalation.go split from slice 1.
//
// public.docker_images_status_type has exactly three labels (confirmed live:
// SELECT enumlabel FROM pg_enum WHERE enumtypid =
// 'public.docker_images_status_type'::regtype): 'building' (CI in progress,
// the column default), 'ready' (images verified in registry), 'failed' (CI
// workflow failed). See doc/db/table/public_upgrade.md's docker_images_status
// row for the same three-way contract.
type imageClaimDecision int

const (
	// imageClaimReady — docker_images_status='ready'. Claim exactly as before
	// this gate existed; no behavior change on the common path.
	imageClaimReady imageClaimDecision = iota
	// imageClaimWait — 'building', within the grace window. Do NOT claim.
	// This is the class-A wait in its cheapest form: waiting in 'scheduled',
	// before any flag is written, outside the crash-resume attempt budget,
	// nothing held. The caller re-probes (verifyArtifacts) and returns; the
	// next tick (executeScheduled runs every 30s off the daemon's
	// heartbeatTicker, service.go's main loop) re-reads the row's current
	// docker_images_status.
	imageClaimWait
	// imageClaimPastGrace — 'building', but scheduled_at is older than the
	// grace window. WEDGE-GUARD (required — the gate may DELAY, never WEDGE,
	// same fail-open-loud posture as the parked-check + statfs rulings):
	// claim anyway, loud. A stale-but-actually-absent image then fails
	// actionably at the existing warm-up pull (the pre-destructive B
	// fail-fast this gate deliberately does not touch) — better than
	// silently starving a row of the tick forever if verifyArtifacts's own
	// registry probe is ever wrong or delayed.
	imageClaimPastGrace
	// imageClaimFailed — 'failed' (CI workflow failed, or verifyArtifacts's
	// own manifestTimeout grace already gave up — see markImagesFailed). Do
	// NOT claim. Permanent until a human re-registers/re-schedules; no
	// grace-based override — retrying a row whose CI is known to have failed
	// cannot succeed by waiting longer, unlike 'building'.
	imageClaimFailed
)

// evaluateImageClaimGate is the PURE decision (no I/O) for whether a
// 'scheduled' row's claim UPDATE should proceed, given its
// docker_images_status and how long it has been scheduled.
//
// grace is bounded off scheduledAt (the row's own timestamp) — NOT a
// wall-clock heuristic that re-derives what verifyArtifacts already tracks.
// Callers pass manifestTimeout (service.go, shared with verifyArtifacts's own
// CI-failure grace) so the two independent "give up waiting" windows — this
// gate's claim-anyway and verifyArtifacts's mark-failed — stay the same
// duration by construction, not by convention.
//
// Any dockerImagesStatus value other than the three enum labels (a future
// enum addition, or a NULL somehow reaching here) falls through the switch's
// default to the same handling as "building" — conservative-wait, never a
// silent claim of an unverified image set.
func evaluateImageClaimGate(dockerImagesStatus string, scheduledAt, now time.Time, grace time.Duration) imageClaimDecision {
	switch dockerImagesStatus {
	case "ready":
		return imageClaimReady
	case "failed":
		return imageClaimFailed
	default: // "building", or an unrecognised future value — treat as building
		if now.Sub(scheduledAt) > grace {
			return imageClaimPastGrace
		}
		return imageClaimWait
	}
}
