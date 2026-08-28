---
id: STATBUS-306
title: >-
  parked-listener-deaf-for-life: a daemon that parks during an outage can never
  hear NOTIFY again — the nil-conn start leaves the restart guard stuck
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-28 20:01'
updated_date: '2026-08-28 21:30'
labels:
  - upgrade
  - cli
dependencies: []
priority: high
type: bug
ordinal: 299000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a parked box must stay REACHABLE — alive-idle means alive to the next poke, not deaf until someone restarts the unit. Today, any daemon that parks during a db outage loses its NOTIFY listener for the rest of the process's life.

THE MECHANISM (traced in service.go by the mechanic during STATBUS-305's arc work, confirmed against the live run's journal): recoveryRollback's park path closes the connections before returning (service.go:3007-3013). Run() then reaches its one-and-only startListenLoop call for this boot with d.listenConn == nil. 294's guard makes this LOUD and safe (the 'NOT listening' announce line, clean return) — but startListenLoop sets d.listenCancel non-nil BEFORE the goroutine runs (:2579-2593), and the nil-conn early return never clears it. Every later `if d.listenCancel == nil { startListenLoop }` guard in the idle main loop (:2448, :2481, :2494, :2518) is permanently false; only stopListenLoop clears it, and nothing calls that on an idle parked box. Result: `./sb upgrade register`'s NOTIFY upgrade_check ('Poked the service to prepare it', :5223-5226) is sent into a daemon that can never hear it again. The queryConn side keeps reconnecting fine — different connection.

THE IMPACT, bounded but real: the box is not dead — the 6-hour discovery ticker (hardcoded, :3578) still fires, so reactivity degrades to once-per-6h instead of on-poke. But every park-during-outage leaves an operator who schedules or registers an upgrade waiting silently for hours, with the service showing active and the poke reported sent. Observed live in 305's arc: docker_images_status stalled at '?' because verifyArtifacts only runs from discover(), which the dead listener never triggers.

THE FIX SHAPE (engineer implements; the 294 file's ownership rules apply): the nil-conn early return in listenLoop (or its caller) must leave the system able to TRY AGAIN — clear the listenCancel guard state (with the done-channel bookkeeping kept consistent) so the idle loop's existing restart guards can start a real listener once a connection exists again. The fix must preserve 294's ownership design (conn passed by value, no shared-field reads in the loop) and its loud announce. Test: the 294 test file's DB-free idiom extends — after a nil-conn start, the guard state must permit a subsequent start; mutation-check that the pre-fix state (guard stuck) reds it.

DISCOVERED-BY chain, for the record: 294 (crash) → 299 (watchdog kill) → 305 (doctrine vs stale assertion) → this — each fix made the next layer observable; this one was found because 305's PARK terminal kept the daemon alive long enough for its deafness to matter.

WHAT IS ACHIEVED: a parked box hears the next poke; alive-idle means reachable.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-28 21:30
---
LANDED at fbb8a14e7 and CLOSED (service.go +37 of which 5 code, listenloop_ownership_test.go +105). The fix improved on the ticket's own shape: startListenLoop refuses a nil conn BEFORE creating any guard state — indistinguishable-from-never-started holds for every consumer BY CONSTRUCTION (nothing was ever set), where the ticket's clear-the-guard shape would have owed two-field consistency at every exit forever. 294's ownership design untouched; listenLoop's own nil guard kept as second-line defence (noted no longer production-reachable); the announce now truthfully promises listening resumes when a connection returns. Tests pin STATE (both guard fields nil) and BEHAVIOUR (a second start reaches its work — the announce appears twice; pre-fix once, silently swallowed at the stuck guard); RED 2/2 by restoring the pre-fix shape; full uncached suite + -race green, with the stdout-capture helper designed against the shared-global race class up front. Also on the record, engineer's own near-miss: a wrong-cwd grep almost reported 'zero functional lines' — caught because --stat contradicted it and the when-a-check-disagrees-read-the-artifact rule applies to reporting commands too. Rides rc.17: a parked box now hears the next poke.
---
<!-- COMMENTS:END -->
