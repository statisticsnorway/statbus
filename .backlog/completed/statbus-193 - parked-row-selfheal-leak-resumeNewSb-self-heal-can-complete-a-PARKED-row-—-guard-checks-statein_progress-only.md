---
id: STATBUS-193
title: >-
  parked-row-selfheal-leak: resumeNewSb self-heal can complete a PARKED row —
  guard checks state='in_progress' only
status: Done
assignee: []
created_date: '2026-07-18 13:27'
updated_date: '2026-07-23 15:54'
labels:
  - upgrade
  - recovery
  - install-recovery
dependencies: []
references:
  - cli/internal/upgrade/service.go
priority: medium
ordinal: 194000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a parked row resolves only by a deliberate un-park (./sb install) or displacement by a fix release — never by an automatic path quietly completing it.
> FOUND: 2026-07-18, by the architect during the STATBUS-192 frozen-diff review (out-of-scope observation recorded on STATBUS-192; pre-existing, NOT introduced by the 192 fix).
> STAGE: triage — architect rules disposition, then engineer-or-mechanic build if ruled a change.

THE OBSERVATION: resumeNewSb's self-heal path can complete a PARKED row. Its guard checks state='in_progress' only — and a parked row IS in_progress with recovery_parked_at set, so the guard does not exclude it. This contradicts the deliberate-un-park-only principle in WORDING, though not in the STATBUS-160 doctrine's outcome (the row still ends in a legitimate terminal state).

WHY IT MATTERS: parked rows are skipped by every automatic resume by design (the 135 parked-skip guard genre); an automatic path that can complete one is the lone exception to that invariant. Even if the outcome is benign today, the asymmetry is the kind of wording-vs-behavior gap that misroutes future reasoning about park semantics.

SCOPE NOTE: do not conflate with STATBUS-192's completeInProgressUpgrade path (which carries the parked-skip guard first, correctly). This is resumeNewSb's own guard.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect rules the disposition: add the parked-skip guard to resumeNewSb's self-heal, or bless the current behavior in writing (doc + code comment naming why parked-complete is acceptable here)
- [x] #2 The ruled outcome is built and its oracle named (structural test or arc leg) — or the bless is recorded on the ticket and in the code
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-18 14:38
---
DISPOSITION RULING (architect, 2026-07-18, AC#1) — GUARD, not bless. Parked rows must not complete via resumeNewSb's self-heal.

WHY GUARD:
1. The deliberate-exit contract is load-bearing, not wording. A park fires ONE siren and promises the operator the state persists until THEY act — re-trigger via a fix release (claim displaces the park to superseded, STATBUS-159) or ./sb install un-park. A third, automatic, silent exit erases a siren state — the no-standing-self-heal-paths doctrine.
2. REACHABILITY UPGRADE — since STATBUS-192 shipped this is real, not theoretical: the 192 health-fail park leaves containers UP at target (compose succeeded, health failed past warmup). If the cause clears by the next daemon boot, the self-heal branch's three gates all pass (containers-at-target :6802 ✓, no-pending :6820 ✓, healthCheck :6824 now ✓) and the parked row quietly completes — setting error = NULL, wiping the parked narrative from the very row an operator was paged to investigate.
3. The interim state a guard leaves — serving box + parked in_progress row — is truthful ('attention required'), not a completed-lie, so there is no STATBUS-160 tension. In the NSO frame the operator's fix + install.sh un-parks and the fresh attempt completes in seconds on an already-serving box.

BUILD SHAPE (small; engineer or mechanic with this design):
1. PRIMARY, loud: at the top of the `ok` branch (:6802, before the HasPending gate), read park state via the existing upgradeParkedReason(ctx, flag.ID) with the SAME 42703 fail-open precedent as completeInProgressUpgrade (:2889); if parked → log.Printf named skip ('resumeNewSb: containers healthy at target but row %d is PARKED (%s) — NOT self-healing; a parked row resolves only by a fix-release re-trigger or ./sb install un-park') and fall through to the continuation — whose STATBUS-046 budget-section parked-skip returns the unit to alive-idle with the flag kept (review verifies that landing).
2. BELT, atomic: the self-heal UPDATE (:6850-6852) gains `AND recovery_parked_at IS NULL` — the same guard bytes parkUpgrade itself uses (:6671). Covers TOCTOU and the fail-open read. A parked row hitting the belt yields ErrNoRows → the EXISTING 'fall through to continuation' path (:6847-6849) — no new disposition.
3. Schema premise (engineer confirms at build; expected to hold by construction): recovery_parked_at's migration ≤ DaemonSchemaFloor so the boot migrate ships the column before resumeNewSb runs — TestDaemonSchemaFloorBumpGuard (cli/internal/migrate/daemon_floor_test.go:95) structurally forces daemon-relation migrations at or below the floor.
4. ORACLE (AC#2): (a) structural pin in recovery_escalation_test.go's genre — extractFuncBody(resumeNewSb), assert the self-heal UPDATE contains 'AND recovery_parked_at IS NULL' and the parked-read precedes it; (b) run proof — extend the EXISTING postswap-health-park-arc with one leg: after the park lands, restart the daemon unit once and assert the row is STILL parked in_progress (not completed), unit alive-idle, flag present. Caveat the engineer resolves in the plan: if the fixture's health is still failing at the restart, the healthCheck gate (:6824) does the skipping and the leg under-proves the new guard — name which state the restart lands in; if serving-at-target-while-parked can't be produced from the existing fixture, the structural pin + the alive-idle regression leg carry it. Do NOT build a new paid arc solely for this.
5. Architect frozen-diff review before commit (recovery safety-core, same lane as 192).

Queueing: no urgency — behind 170 AC#3 per the foreman's sequencing; it is a latent leak with a siren-erasure consequence, not an active breaker.
---

author: architect
created: 2026-07-20 15:46
---
FROZEN-DIFF REVIEW (architect, 2026-07-20) — verdict: SHIP, zero amendments. All three files byte-verified against the comment-#1 design:

service.go: PRIMARY parked-read is the FIRST branch of the self-heal gate chain (inside the containers-at-target arm — no extra DB read on the normal mismatch path), 42703 fail-open with a log line that names the belt as the remaining protection; loud skip line naming the park reason + both deliberate exits; BELT = parkUpgrade's exact guard bytes on the self-heal UPDATE, ErrNoRows → the existing continuation fall-through with the comment updated truthfully (terminal OR PARKED). The schema premise is even documented in-line (20260703210000 ≤ floor 20260712024457 — confirmed, the fail-open is belt-and-suspenders by construction). One accepted non-issue: HasPending is computed before the branch chain even on a parked pass — one wasted read on a rare path, not worth the reorder.

Structural pin: correct ordering semantics — strings.Index finds the EARLIEST upgradeParkedReason, so if the new read were removed while the continuation's later one survived, the precedence assert fails (the pin cannot be satisfied by the wrong read). Belt assert pins the guard bytes on the UPDATE's own line.

Arc leg — the refinement is APPROVED and better than my design's caveat handling: because the guard is the FIRST branch, its journal line ('is PARKED … NOT self-healing') can only print when containersAtFlagTarget passed AND the row is parked — so on this still-health-failing fixture the line's presence behaviorally proves GUARD-BEFORE-GATE placement (a regression moving the guard after the health gate reds the arc: the gate would skip silently and the line never prints). The serving-while-parked state my design worried about is not needed; the discriminator is placement, not box health. The bounded journal-tail grep matches the file's local convention and cannot hit the runner-health SIGPIPE class (small buffer, single write).

AC#2 stays UNCHECKED until the arc leg runs green — the run is the oracle. BUNDLED DISPATCH APPROVED: one harness run with scenarios="postswap-health-park deploy-status-proof" closes this ticket's arc oracle AND 170 AC#4 together — the two arcs are independent scenarios on separate VMs, no coupling.
---

author: foreman
created: 2026-07-23 14:59
---
KING RULING (2026-07-23): 193 is IN the stable-cut gate. Build committed a8b4bdcf6 (architect frozen-diff review: SHIP, zero amendments — comment #2); structural pin passing; the arc-leg run-proof (postswap-health-park's restart leg asserting the parked-guard journal line) is in the bundled harness dispatch now running. AC#2 checks on its green.
---

author: foreman
created: 2026-07-23 15:54
---
AC#2 PROVEN — TICKET COMPLETE (2026-07-23, run 30017980913, postswap-health-park=SUCCESS, explained green): the arc's PASS narrative names the guard directly — 'the STATBUS-193 self-heal parked-guard firing on each [containers-at-target + parked → NOT self-healing, short-circuiting the health gate]' across the two extra parked restarts; the row never rolled back, never completed while parked; the genuine fix release (C) then arrived, displaced the park, and completed with data intact — both deliberate exits intact, the automatic exit dead. Structural pin was already passing. Guard shipped a8b4bdcf6; King ruled the ticket IN the stable-cut gate (comment #3) — gate satisfied same day.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
resumeNewSb's self-heal can no longer complete a PARKED row. Two fail-closed layers shipped in a8b4bdcf6: a loud parked-read as the FIRST branch of the self-heal gate chain (named journal skip, falls through to the alive-idle continuation with the flag kept) and the parkUpgrade guard bytes (AND recovery_parked_at IS NULL) on the self-heal UPDATE itself. Guard-first placement is behaviorally proven: its journal line can only print when containers are at target AND the row is parked, so the postswap-health-park arc's restart legs asserting the line prove guard-before-health-gate; run 30017980913 delivered exactly that on each parked restart, with the park surviving until a genuine fix release displaced it. A park's siren now persists until the operator acts — fix release or installer — never erased by an automatic path.
<!-- SECTION:FINAL_SUMMARY:END -->
