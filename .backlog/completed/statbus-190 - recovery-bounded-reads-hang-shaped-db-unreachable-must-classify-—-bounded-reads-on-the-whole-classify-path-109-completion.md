---
id: STATBUS-190
title: >-
  recovery-bounded-reads: hang-shaped db-unreachable must classify — bounded
  reads on the whole classify path (109-completion)
status: Done
assignee: []
created_date: '2026-07-15 04:49'
updated_date: '2026-07-15 06:23'
labels:
  - install-recovery
  - upgrade
  - safety-core
  - defect
dependencies: []
priority: medium
ordinal: 191000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: no shape of db-unreachable — fast-refusal OR hang — can bypass the recovery classify-then-act; every transient enters the named in-process backoff instead of watchdog exit-restart churn.

ORIGIN (STATBUS-071 transient-db-backoff arc, run 29388951223, 2026-07-15 — the arc's first product catch): docker pause produced a HANG-shaped unreachable (connections stall, no error); the resuming verify's observed-state read (service.go:2611) is unbounded and the pass doesn't heartbeat outside backoffRetry, so the hang never reached classification — CauseDBUnreachable fires only on fast-fail reads — and systemd's watchdog killed the unit at 2min ("Failed with result 'watchdog'"). The hang class (network partition, silent packet drop, frozen container, NAT timeout) is a real NSO production mode and bypassed the entire STATBUS-109 design. The backoff PROBE spec already bounds its tries (5s ctx); the VERIFY read was the gap.

RULED FIX SHAPE (architect, 2026-07-15, on STATBUS-071):
- Bounded reads on the WHOLE classify path: every DB read between recoverFromFlag entry and backoff engagement — including loadLogRelPath at the function top (a hang there blocks before any phase branch; on timeout it degrades to its existing nil-fallback) and every read inside verifyUpgradeObservedStateEx.
- One shared constant = the probe's own 5s per-try bound; no scattered literals.
- A bounded-read timeout inside the verify classifies as ObservedPositionUnreadable + CauseDBUnreachable — hang and fast-refusal become ONE class at the classifier (the operator's network doesn't care which way the socket died).
- NO new heartbeat: with 5s-bounded reads the pass reaches the self-heartbeating backoffRetry within seconds; WatchdogSec stays the outer net.
- VERIFY EnsureDBUp/connect's existing bounds rather than assuming (the run just proved one "obviously bounded" read wasn't).
- Unit test stubbing a refused connection covers the fast-refusal classification at zero VM cost; the hang class is the arc's job.

PROCESS: engineer builds; ARCHITECT frozen-diff review (King's rule — foreman/architect only for code review; this is recovery safety-core); foreman commits. ORACLE: the transient-db-backoff arc re-run (KEEPS docker pause — the stronger hang-class inducement, ruled) — both arms green flips the last release-gating map row.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every DB read between recoverFromFlag entry and backoff engagement is bounded by the shared 5s constant (loadLogRelPath + all verifyUpgradeObservedStateEx reads); EnsureDBUp/connect bounds VERIFIED not assumed
- [x] #2 A hung read classifies as ObservedPositionUnreadable + CauseDBUnreachable and enters the backoff (arc-proven: pause-induced hang → backoff → resolve/exhaust arms both green)
- [x] #3 Unit test: a refused connection classifies identically (fast-refusal and hang are one class)
- [x] #4 Architect frozen-diff review before commit; no new heartbeat machinery
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-15 05:35
---
FROZEN-DIFF REVIEW (architect, 2026-07-15): SHIP, zero amendments. Verified against the ruling point by point: (1) ONE named constant (recoveryReadTimeout, recovery_backoff.go) carrying the run-2 finding + the no-new-heartbeat rationale in its doc; the probe's 5s literal folded into it — no scattered literals. (2) loadLogRelPath bounded with degrade-to-""-fallback exactly as scoped (the first classify-path read; a hang there blocked before any branch). (3) The verify's db.migration read bounded, with the timeout flowing into the EXISTING queryErr→CauseDBUnreachable path — hang and fast-refusal are now ONE class at the classifier, as ruled. (4) Bounds evidence accepted: connect 5m, EnsureDBUp 60s, exactly two unbounded reads existed — matching run 2's two hang points. (5) The negative assertions (QueryRow(ctx,) are safe: each function carries exactly one read, consistent with the block-scan.

TEST-CHOICE RULED: the STRUCTURAL PIN IS SUFFICIENT — no STATBUS-182 DB-gated behavioral machinery. Grounds: pgx.Conn is a concrete struct, so a live-but-refusing conn is not constructible DB-free without an interface refactor out of all proportion; and the transient-db-backoff arc (keeping docker-pause, the stronger inducement) IS the behavioral oracle for the hang class end-to-end — a DSN-lane duplicate would be a second oracle for the same behavior against the one-canonical-oracle discipline. The structural test pins what must not drift (boundedness, the shared const, the single-class classification); the arc proves what must run.

Foreman: commit + chain push + re-dispatch the arc — run 3 is the release-gating oracle.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped as d471f6e2e and arc-proven by transient-db-backoff run 29393095941 (both arms green). The recovery classify path's exactly-two unbounded DB reads (loadLogRelPath at recoverFromFlag entry; verifyUpgradeObservedStateEx's db.migration read) are bounded by one named constant (recoveryReadTimeout = 5s, the backoff probe's own per-try bound with its literal folded in); a bounded-read timeout flows into the existing queryErr → ObservedPositionUnreadable + CauseDBUnreachable path, so hang-shaped and fast-refusal unreachable are ONE class at the classifier. No new heartbeat machinery — bounded reads reach the self-heartbeating backoffRetry within seconds; WatchdogSec stays the outer net. Bounds on connect() (connectTimeout=5m) and EnsureDBUp (waitForDBHealth 60s) verified with citations, not assumed. TestClassifyPathReadsBounded pins the constant-bound reads and the one-class property structurally (architect ruled the structural pin sufficient — pgx.Conn is not constructible DB-free, and the arc, which keeps docker pause as the stronger hang inducement, is the single canonical behavioral oracle). Live proof: run 3 classified the paused-DB hang in 11s where run 2 had watchdog-wedged; run 4 proved both backoff arms end-to-end. Engineer built; architect frozen-diff reviewed (SHIP, zero amendments); foreman verified independently and committed.
<!-- SECTION:FINAL_SUMMARY:END -->
