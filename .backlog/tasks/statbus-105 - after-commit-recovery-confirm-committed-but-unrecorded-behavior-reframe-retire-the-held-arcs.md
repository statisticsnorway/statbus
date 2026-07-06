---
id: STATBUS-105
title: >-
  after-commit-recovery: verify the box rolls back per 013 — overnight reached
  'completed' (suspected deviation)
status: To Do
assignee: []
created_date: '2026-06-20 10:48'
updated_date: '2026-07-06 16:06'
labels:
  - upgrade
  - recovery
  - install-recovery
dependencies:
  - STATBUS-071
priority: medium
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a torn migration (committed but unrecorded) must end rolled_back — restore to known-good, operator retries; never certified completed.
> BENEFIT: either we prove the box honors the King's rolled_back ruling on the one state recovery cannot reconcile, or we catch it silently certifying torn state as completed (the overnight observation) — a real integrity gap — and fix it. One measurement decides; both outcomes are worth more than the current unknown.
> STAGE: Stage 1.
> COMPLEXITY: mixed — mechanic instruments the arc re-run (the measurement); architect rules on the verdict; engineer fixes if a gap is confirmed.
> DEPENDS ON: STATBUS-071 (the after-commit kill arcs are the measurement vehicle).
> Housekeeping: labels say "auth-email, not-install-upgrade" — plainly wrong; fix in the apply pass.

---

Per STATBUS-013 (THE SPEC, confirmed verbatim with the King 2026-06-08), a crash in the commit↔record gap MUST end ROLLED_BACK: restore the pre-upgrade backup → operator retries. This task verifies the box ACTUALLY does that, and fixes it if it does not.

THE OBSERVATION (overnight 2026-06-19/20): the after-commit-kill arcs reached upgrade-row state 'completed', and NEVER passed through 'rolled_back' in 600s. By the recovery logic that is the SUSPECTED DEVIATION — the box "being clever" (certifying a torn migration as completed) instead of restoring → rolled_back, which 013 forbids.

WHY rolled_back is forced (logical derivation, the King's "derive don't ask" method): recovery sees the killed migration V as PENDING (not in db.migration); the shortcut-to-completed (resumePostSwap self-heal) is GATED on HasPending=false, so it is blocked; the box must re-run migrate-up; the non-idempotent re-run hits "relation already exists" → migrate fails → postSwapFailure → restore backup → rolled_back. So a torn/pending V CANNOT legitimately reach 'completed' on the interrupted attempt; 'completed' is reachable only if V was already recorded at recovery (premise not met) or by a separate later attempt.

THE ARCS WERE RIGHT: the held after-commit arcs (:844 d18789b55, :845 d28760544) assert rolled_back — matching 013. KEEP that assertion.

THE ONE MEASUREMENT (the oracle; durable run-artifacts — the VM journal is ephemeral): an instrumented re-run capturing, for the killed upgrade's row — was V in db.migration at recovery time (pending or not), and did the row EVER pass through rolled_back / did a restore fire.
- V pending + row reached completed with NO restore → REAL GAP (box deviates from 013) → FIX the recovery so a torn/pending migration restores → rolled_back (confirm the self-heal's HasPending gate holds and nothing else marks a pending torn migration completed).
- V already recorded at recovery → the killed-before-recorded premise wasn't met; no gap; understand why V got recorded.

RELATION: STATBUS-013 = the spec (rolled_back); STATBUS-097 = retired (atomicity was the wrong premise).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Instrumented re-run captures, on durable run-artifacts: was the killed migration V in db.migration at recovery (pending or not), and did the upgrade row EVER pass through rolled_back / did a restore fire
- [ ] #2 Verdict recorded: box HONORS 013 (reaches rolled_back, no gap) vs DEVIATES to completed (real gap) — from the measurement, not presupposition
- [ ] #3 If a gap: the recovery is fixed so a torn/pending migration restores → rolled_back per 013; the held arcs keep asserting rolled_back
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer (board sweep)
created: 2026-07-06 15:59
---
FOLDED IN from STATBUS-013 (merged 2026-07-06): 013's King-ratified spec — a crash between a migration committing and being recorded MUST end rolled_back — is NOT superseded and lives here as its canonical spec+verify home; 105 restates the spec verbatim and owns the open measurement. 013's dead mechanics (the inject/env analysis + the old fabricated scenario) predate the boot-migrate reality (STATBUS-044 comments #5–#6) and the budget hoist (cc660280f) and are dropped. The arc coverage asserting rolled_back lives on STATBUS-071.
---
<!-- COMMENTS:END -->
