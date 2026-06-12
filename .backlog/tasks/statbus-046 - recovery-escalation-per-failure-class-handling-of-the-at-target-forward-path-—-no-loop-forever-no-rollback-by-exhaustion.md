---
id: STATBUS-046
title: >-
  recovery-escalation: per-failure-class handling of the at-target forward path
  — no loop-forever, no rollback-by-exhaustion
status: To Do
assignee:
  - architect
created_date: '2026-06-12 22:15'
labels:
  - install-recovery
  - upgrade
  - recovery
  - design
  - needs-king-ratification
  - operator-ux
dependencies: []
references:
  - STATBUS-039
  - STATBUS-044
  - cli/internal/upgrade/service.go
  - doc/diagrams/upgrade-timeline.plantuml
  - doc/diagrams/upgrade-lifecycle.plantuml
priority: high
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING DIRECTIVE (2026-06-13, direct): the "loudness" question cannot be answered in general — each kind of error has a different cause and needs its own sensible handling. Waiting for something that GETS ready deserves leniency; something that will NEVER get ready must fail fast and actionable; looping forever (rune's shape) is not an option — it eventually exhausts disk on top of the original problem. Each case goes in the diagram; each case gets a decided handling.

EMPIRICAL ANCHOR: systemd StartLimit demonstrably cannot bound this loop — rune restarted 10,229 times because the ~150s watchdog-kill cadence sits under the burst rate (≈4 starts per 600s window). The bound must be an UPGRADE-ATTEMPT budget owned by the recovery itself, not a unit-restart budget.

## The four failure classes (cause-based, classified AT THE CALL SITE — each postSwapFailure caller knows its own step's nature; the codebase already carries named Err* codes per step and isConnError discrimination, so the knowledge exists where the classification happens)

A. READINESS — the thing will become ready (DB container starting, app/REST warming, reconnect racing a restart). Leniency correct: in-attempt bounded waits (already exist: waitForDBHealth 30s, health-check 3 tries) + a SMALL cross-attempt forward-retry budget (proposal: 3 automated attempts), because a fresh attempt genuinely can succeed.

B. DETERMINISTIC — will never succeed by retrying (config-generate template error; registry 404 on a tag that should exist; SQL/constraint errors on the no-op at-target migrate; persistent app health failure past warmup = the running version cannot serve; CHECK violations — where markPgInvariantTerminal already fails fast today, the precedent). NO automated retry: park on FIRST occurrence with the named actionable error.

C. RESOURCE EXHAUSTION — never improves alone and RETRYING AMPLIFIES IT (disk full, connection-pool exhaustion). Park immediately with the named resource error; the attempt budget itself is what prevents the loop from CAUSING this class.

D. CRASH/KILL mid-attempt (watchdog SIGABRT, OOM, reboot) — the loop driver; the underlying cause is one of A/B/C but unknowable at death. Counts against the same budget: the attempt counter increments at attempt START, so a crash self-counts.

## PARK-DEGRADED — the mechanism that replaces loop-forever (proposal for ratification)

When the budget exhausts (A/D) or a B/C failure fires once: the row is PARKED — stays in_progress (forward-only preserved; rollback remains reachable ONLY via a positively-Behind verdict, never via exhaustion), gains a durable parked marker + attempt count + the named reason (proposal: recovery_attempts int + recovery_parked_at timestamptz columns — queryable, no enum churn; admin UI shows WHY). The service then SKIPS resume for the parked row on every boot/tick (one loud log line; degraded callback/siren fires ONCE), stays alive and idle — serving its normal loop, reachable by NOTIFY. No crash-loop, no journal/log bleed, no disk creep.

UN-PARK = exactly the product's two operator actions, nothing new: (1) re-trigger the upgrade (NOTIFY/apply — a fresh deliberate attempt with a fresh budget), or (2) ./sb install (a deliberate inline attempt). Each deliberate trigger is ONE attempt, not a loop.

## Per-step mapping (the diagram rows — each gets a decided handling)
- config generate → B (park first failure)
- docker pull → split by error: unreachable/timeout=A; manifest-unknown=B; disk=C
- db up / waitForDBHealth → A
- reconnect → A
- migrate (no-op at-target) → conn-error=A; SQL-error=B
- start services (step 11) → daemon hiccup=A; compose/config error=B; disk=C
- app health → warmup=A (in-attempt tries); persistent-past-warmup=B
- maintenance-off/archive/completion writes → conn=A; constraint=B (existing fail-fast precedent)
- watchdog/OOM/reboot death → D (budget self-count)

## Sequencing
1. King ratifies the classes, the per-step table, the budget value, and the park mechanics (or redirects).
2. Implementation (code + the row columns + the call-site classification).
3. DIAGRAMS UPDATED IN THE SAME COMMIT AS THE SHIPPED HANDLING (docs describe the present — never ahead of code): upgrade-timeline gains the per-class routing at the failure chokepoint; upgrade-lifecycle gains the parked representation of in_progress.
4. STATBUS-044's held scenario (3-postswap-resume-died-rollback, the pinned-kill shape) then asserts the DECIDED behavior: budget consumed → parked + named reason + unit alive-idle, NOT NRestarts climbing forever, NOT rolled_back.

RELATION: resolves the loudness fork that STATBUS-044 is holding on; builds on STATBUS-039's ground-truth routing (this design changes only HOW LONG and HOW LOUD forward is tried — never the direction).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King ratifies (or redirects) the four failure classes, the per-step mapping, the attempt-budget value, and the park-degraded mechanics
- [ ] #2 Implementation: call-site classification + attempt budget + park marker; rollback remains reachable ONLY via a Behind verdict, never via exhaustion; parked unit stays alive-idle (no crash loop, no disk bleed)
- [ ] #3 Both diagrams updated in the SAME commit as the shipped handling — every failure case visible with its decided handling
- [ ] #4 STATBUS-044's held scenario rewritten against the decided behavior and green
<!-- AC:END -->
