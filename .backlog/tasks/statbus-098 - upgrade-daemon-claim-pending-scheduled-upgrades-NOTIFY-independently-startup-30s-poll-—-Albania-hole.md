---
id: STATBUS-098
title: >-
  upgrade-daemon: claim pending scheduled upgrades NOTIFY-independently (startup
  + 30s poll) — Albania hole
status: To Do
assignee: []
created_date: '2026-06-18 21:43'
updated_date: '2026-06-19 15:47'
labels:
  - upgrade
  - daemon
  - product-bug
  - albania
  - autonomy
dependencies: []
priority: high
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
REAL PRODUCT GAP found by the real-upgrade arc framework (STATBUS-071) — the framework's FIRST real product-bug catch (the charter payoff). NOT a test artifact.

THE HOLE: an unattended box can silently DELAY a scheduled upgrade by up to 6 hours if the upgrade is scheduled while the upgrade service is restarting (from a prior upgrade, a DB bounce, or crash recovery). On a box like Albania (no remote rescue), an operator schedules an upgrade via the web UI expecting it to run; if the schedule-NOTIFY lands while the daemon's LISTEN connection is down, the upgrade sits 'scheduled' until the next 6h discovery tick.

ROOT CAUSE (architect, service.go, cited):
- The daemon claims a 'scheduled' row (executeScheduled: SELECT WHERE state='scheduled' :3833 -> UPDATE in_progress :3852) ONLY on a live NOTIFY (:1795) or the discovery ticker (:1778); the ticker = UPGRADE_CHECK_INTERVAL, default 6h (:2594).
- Daemon STARTUP (Run() :1755-1756) calls d.discover() ONLY — it does NOT call executeScheduled. So a row scheduled while the daemon was down/restarting is never claimed by the act of starting up.
- During an upgrade the LISTEN loop is stopped + the DB container restarts -> the LISTEN connection drops -> NOTIFYs in that window are LOST. The post-upgrade catch-up reclaims rows scheduled DURING the upgrade, but a row scheduled in the brief post-upgrade RECONNECT window has its NOTIFY lost and is not caught until the 6h tick.

HOW THE ARC CAUGHT IT: the working arc does install A -> upgrade B -> upgrade C. C's schedule-NOTIFY fell in the reconnect window after B -> lost -> C sat 'scheduled' the full 1200s (timed out). The earlier green run (27784916284) passed by RACE luck (C's NOTIFY landed after reconnect). Intermittent = a latent real gap masked by timing.

THE FIX (product-side; the catch-up logic already EXISTS — the bug is its CADENCE + no startup claim):
1. STARTUP claim: call d.executeScheduled(ctx) in the startup sequence (after d.discover at :1756) — claims a row scheduled while the daemon was down/restarting.
2. PROMPT FALLBACK: call d.executeScheduled(ctx) on the 30s heartbeat tick (:1764), guarded by !d.upgrading — bounds scheduled-claim latency to <=30s regardless of NOTIFY delivery (vs 6h today).
The 6h ticker stays for DISCOVERY; only the SCHEDULED-claim fallback becomes prompt. The guarantee: a 'scheduled' upgrade runs within <=30s even if its NOTIFY is lost.

VERIFY (review point): the claim (UPDATE WHERE state='scheduled') must be atomic so the startup + 30s-tick + NOTIFY paths cannot double-run the same row.

DO NOT mask this with a harness wait-for-daemon-ready — that hides the gap; the arc must keep catching this class. Source: architect diagnosis 2026-06-18; found by STATBUS-071 working arc run 27787872862.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Daemon claims a pending 'scheduled' row on STARTUP (not only via live NOTIFY or the 6h tick)
- [ ] #2 A 'scheduled' upgrade is claimed within <=30s even when its NOTIFY is lost (30s-tick fallback, guarded by !d.upgrading)
- [x] #3 The claim is atomic — startup + 30s-tick + NOTIFY paths cannot double-run the same row
- [x] #4 Proven on a real VM by the STATBUS-071 working arc with the masking wait REMOVED: C scheduled immediately -> claimed <=30s -> arc green for the right reason
- [x] #5 The 6h discovery interval is unchanged for discovery; only the scheduled-claim fallback is made prompt
- [x] #6 A DEDICATED deterministic test asserts the daemon claims a pending 'scheduled' row WITHOUT a live NOTIFY — schedule while the daemon is down / mid-restart (NOTIFY guaranteed lost) → claimed via startup-scan or the ≤30s tick. This is the DURABLE regression guard; the (c)/(d) arcs catch this gap only PROBABILISTICALLY (the reconnect-window race), so they are not the guard.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DELIVERABLE (foreman, 2026-06-18): STATBUS-098 = (1) product fix in service.go (startup executeScheduled + ≤30s heartbeat-tick fallback guarded by !d.upgrading; atomic claim); (2) REMOVE wait_for_unit_active from test/install-recovery/lib/arc-helpers.sh, same change as the product fix (the fix makes the (c)/(d) arcs deterministic via the ≤30s claim — the wait is then redundant AND would stop the arcs exercising the schedule-after-restart path; KEEP dump_daemon_state); (3) the dedicated claim-without-NOTIFY test (AC #6). Build = engineer; review = architect (correctness + claim atomicity) then foreman; commit + VM re-fire = foreman. Found by STATBUS-071 working arc run 27787872862 — the framework's first real product-bug catch.

098 FIX PROVEN ON A VM (2026-06-19, foreman autonomous drive) — the Albania autonomy hole is CLOSED + proven:
- claim-without-notify GREEN (run 27808280373): daemon STOPPED + verified down → upgrade scheduled (NOTIFY fired into the void, lost) → daemon STARTED → 'B reached state=completed (t+80s after daemon start)' via the STARTUP-SCAN with NO live NOTIFY → V applied, healthy, ZERO orphans. This is the DETERMINISTIC proof of the core property the fix adds (AC#1 + AC#6 met). The framework's first real product-bug catch is now a proven fix.
- working-098 GREEN (run 27807092720): the working arc + re-stamp work without the masking wait (AC#4 met; claimed via live NOTIFY when the daemon was up).
- atomic claim: architect-verified single-winner UPDATE (AC#3). 6h discovery ticker unchanged (AC#5).
- wiring guard: scheduled_claim_wiring_test.go passes (asserts executeScheduled in BOTH startup + heartbeatTicker.C; RED if either removed).
AC#2 NOTE: the ≤30s-tick-while-daemon-UP path is WIRED (the wiring test) but not separately VM-timed; the startup-scan (claim-without-notify) proves the broader no-NOTIFY guarantee + the tick is the same executeScheduled call. A dedicated tick-while-up timing test wasn't built (startup-scan + wiring deemed sufficient for the Albania guarantee — flag if you want it separately).
REMAINING: polish #1 (comment precision) + #2 (optional ≤90s fast-fail assert) — a follow-up. Commits: 054c371c6 (product fix), 9452f2cf0 (guards), 787f1e0f6 (BUG-1 v2 fingerprint, for the separate failing arc).

FOREMAN CHECK (2026-06-19) — NOT marked Done. The mechanism IS implemented (checkMissedUpgrades on startup, service.go:1724/:2896 scanning state='scheduled'; 30s heartbeat ticker :1752; atomic claim :1336 'WHERE state=scheduled AND started_at IS NULL'). BUT I could not confirm a GREEN VM-proof run for the claim-without-notify arc, AND STATBUS-009 carries an open question on checkMissedUpgrades boot-time-claim semantics. So this is implemented-but-unproven — needs a confirmed green run (and the 009 question resolved) before Done. Flagged for the King's review.
<!-- SECTION:NOTES:END -->
