---
id: STATBUS-046
title: >-
  recovery-escalation: per-failure-class handling of the at-target forward path
  — no loop-forever, no rollback-by-exhaustion
status: To Do
assignee:
  - architect
created_date: '2026-06-12 22:15'
updated_date: '2026-07-03 19:05'
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
documentation:
  - >-
    doc-021 -
    Recovery-escalation-—-the-per-failure-class-allowance-table-STATBUS-046.md
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
REFINEMENT (King review, 2026-06-13 — supersedes the description's class mechanics; .C and .D's budget-counting accepted as described):

.A — READINESS IS TIME-BOUNDED IN PLACE, NOT ATTEMPT-COUNTED. A retry budget was the wrong unit for waiting: each crash-retry re-pays the whole pipeline to reach the same wait. Class A gets a generous, NAMED, per-step time allowance sized to the worst legitimate case, size-scaled where the wait scales with data (DB crash-recovery WAL replay on a Norway-sized volume = many minutes; precedent: the size-scaled MigrateUpTimeout, STATBUS-012). The wait happens IN PLACE within the attempt.

.B — UNIFICATION: ALLOWANCE-PER-CASE, ZERO MEANS DETERMINISTIC. Classification is never by error text alone — it is (step, error, context) → a named allowance. The registry-404 example proves it: during publication (CI still uploading) it is a publication wait (allowance ≈ the upload process's honest worst case, minutes; precedent: markImagesFailed's manifest-timeout grace window in discovery); on an at-target RESUME the image demonstrably existed (containers run it) → no wait helps, external re-publish required → allowance ZERO. General form: "never gets ready" ≡ allowance = 0 (template/SQL/constraint errors are zero-allowance). ONE uniform mechanism everywhere: every failure mode carries a named allowance derived from its cause; ALLOWANCE EXPIRY → PARK, reason naming what was waited for and how long. The four classes become the derivation table for one number per case, not four mechanisms.

.D — THE NEXT ACTION AFTER A CRASH, in order: (1) systemd restarts the service (it has normal duties). (2) Boot recovery: row + flag → ground truth at-target → consult the attempt counter (incremented at attempt START — the crash self-counted). (3) Budget remaining → exactly ONE more forward attempt. Budget proposal: 3, sharpened: the flag records WHICH STEP the attempt died at; two consecutive deaths at the SAME step → park immediately (same-step-twice = deterministic-hang evidence = zero allowance per .B); different steps / reboot = environmental → remaining budget applies. (4) Budget exhausted → PARK: row in_progress + marker + attempt history + dying step; siren fires ONCE with that named story; service returns to its normal loop alive-idle. (5) After park the next action is a HUMAN's, via the product's two actions only — re-trigger or ./sb install — each deliberate trigger buys exactly ONE fresh attempt; the machine never resumes hammering on its own.

RATIFICATION REMAINING: the per-step allowance TABLE (each pipeline step × its failure modes × the derived allowance — the diagram rows), the D budget number (3) + same-step-twice rule, and the park marker columns. Implementation note: the flag already carries per-attempt state across restarts (Phase, BackupPath) — the dying-step record and attempt counter extend the same persisted-flag pattern; the row mirror (recovery_attempts, recovery_parked_at) serves install/UI/queries.

DETAILED ALLOWANCE-TABLE DESIGN WRITTEN (architect, 2026-07-01) -> doc-021. Fills the three ratification-remaining pieces: (1) the per-step allowance TABLE (grounded in the current waits: waitForDBHealth 60s exec.go:1022/1057, MigrateUpTimeout 30m size-scaled, healthCheck retries + waitForRestReady, WatchdogSec=120; systemd StartLimitBurst=5/600s + RestartSec=30 provably can't bound the ~160s/cycle rune loop); (2) the D attempt-budget=3 + same-step-twice->park rule (dying step recorded on the flag; counter increments at attempt START so a crash self-counts); (3) the park-marker columns recovery_attempts int + recovery_parked_at timestamptz. Unified mechanism = one named allowance per (step,error,context): A=readiness time-bound-in-place-size-scaled, B=deterministic=0->park, C=resource=0->park, D=crash->budget. PARK-DEGRADED replaces loop-forever (row stays in_progress, forward-only preserved, rollback only via positively-Behind, un-park only via the 2 operator actions). Composition: 039 sets direction / 046 governs how-long+how-loud before park; 110 makes pre-completion rollback safe / 046's park is the at-target regime; 109 = the class-A in-place wait generalized per step. Sequenced after 110/109 in the recovery-core build. READY FOR KING RATIFICATION (3 asks in doc-021 §Ratification).
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-02 06:27
---
DESIGN WRITTEN → doc-021 (architect, 2026-07-01) — recovery-core unit 3 (sequence 110→109→046→111; 110 COMMITTED 3ff119b8a). Allowance table: per-(step,error,context) allowance — A=readiness (time-bound in place, size-scaled), B=deterministic→park, C=resource→park, D=crash→budget. Attempt budget=3 + same-step-twice→park (counter increments at attempt START so a crash self-counts). Park columns: recovery_attempts int + recovery_parked_at timestamptz; PARK-DEGRADED replaces loop-forever (row stays in_progress, forward-only preserved, ROLLBACK only via a positively-Behind verdict — NEVER exhaustion; un-park only via the 2 operator actions). Composition: 039=direction, 046=how-long/how-loud forward before park (never direction), 110=pre-completion rollback data-safe, 046-park=the at-target/post-completion regime (users+integrators live → can't safely roll back → park not loop), 109=class-A in-place wait generalized. READY FOR KING RATIFICATION — 3 concrete asks in doc-021 §Ratification: (1) the allowance values, (2) budget=3 + same-step-twice, (3) the 2 park columns. NOT started (unit 3, after 110-verify + 109). Verify via 071 arcs (STATBUS-044's held scenario = budget-consumed → parked+named+alive-idle, + per-class A/B/C/D arc).
---

author: architect
created: 2026-07-02 18:24
---
doc-021 EXPANDED with THE STEP LIST (architect, 2026-07-02) — answers the King's ratification gap ('which steps are covered, transient or deterministic'). Grounded first-hand vs master HEAD (executeUpgrade 3983, applyPostSwap 4574, rollback 5650). Per-step walk in 5 phases, each step: (a) what runs (b) failure classes A/B/C/D + concrete example (c) what a class-D crash means (d) inside/outside the budget.

BUDGET BOUNDARY (new ask #4, made explicit): counted from the FLAG WRITE (Phase 1.1, service.go:4140) through the COMPLETED-WRITE + FLAG REMOVAL (Phase 4.2–4.3, :4957/:5001). Phase 0 pre-flight (before the flag) and Phase 5 post-completion cleanup (after flag removal) are OUTSIDE. A Phase-1 (pre-swap) exhaust ROLLS BACK (data-safe via 110's stopped-DB snapshot); a Phase-3 (post-swap at-target) exhaust PARKS (can't roll back — the rune-loop regime). Awaiting King ratification of asks 1–4.
---

author: foreman
created: 2026-07-03 19:05
---
RATIFIED BY THE KING (2026-07-03, decision D3 — verbatim record on STATBUS-127 comment 2). All four asks approved: allowance values as proposed (tunable at build/arc); crash budget = 3 counting PROCESS DEATHS only (temporary errors get time-budgeted backoff, never counted attempts; permanent park on first) + same-step-twice → park immediately; park columns recovery_attempts + recovery_parked_at; the budget boundary = flag-write (service.go:4140) through completed-write + flag removal, phases 0 and 5 outside. The bounce-then-ratify loop that got here: the King required the per-step walk (doc-021 now carries all 44 operations with file:line and per-step classes) and the precise temporary/permanent/crash class model. BUILDABLE after the arc lane validates the 110 seed-fidelity fix + 109 (recovery-core order 110→109→046→111 preserved); the designated verification vehicle is STATBUS-044's held scenario (parked + named reason + alive-idle, not NRestarts-climbing).
---
<!-- COMMENTS:END -->
