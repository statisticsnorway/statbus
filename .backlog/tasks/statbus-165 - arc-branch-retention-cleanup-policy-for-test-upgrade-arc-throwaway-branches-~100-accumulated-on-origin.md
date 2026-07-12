---
id: STATBUS-165
title: >-
  arc-branch-retention: cleanup policy for test/upgrade-arc-* throwaway branches
  (~100 accumulated on origin)
status: To Do
assignee: []
created_date: '2026-07-12 14:54'
updated_date: '2026-07-12 22:40'
labels:
  - git-hygiene
  - not-install-upgrade
dependencies: []
priority: low
ordinal: 166000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every visible branch is live (same star as STATBUS-035).
> BENEFIT: ~100 dead throwaway branches stop drowning `git ls-remote` / branch listings and stop inviting wasted investigation.
> STAGE: Hygiene.
> COMPLEXITY: one architect ruling (retention rule) + one small framework change + one sweep.
> DEPENDS ON: STATBUS-071 (the framework that creates them).

GROUND TRUTH (git ls-remote --heads origin, 2026-07-12): ~100 branches matching `test/upgrade-arc-*-migration-<runid>` plus `red/031-rollback-watchdog`. These are the STATBUS-071 real-upgrade-arc framework's throwaway branches — one pushed per run so CI builds a per-commit image, then never deleted. No retention policy exists.

Shape of the fix (architect to rule the exact rule):
1. The framework deletes its own branch at end-of-run (green or red) once the image digest is recorded — the branch's only job is to trigger the per-commit image build; the COMMIT is authoritative (source-version-authority), the branch is just a trigger.
2. A one-time sweep deletes the ~100 accumulated (verify none is referenced by an open run first).
3. `red/031-rollback-watchdog` gets one owner answer (likely folds into the STATBUS-035 keep-pending walk).

Constraint: never-delete set (master, 11 deploy pointers, db-seed) untouched, as in STATBUS-035.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect rules the retention mechanism (self-delete at end-of-run vs TTL sweep) and where it lives in the 071 framework
- [x] #2 One-time sweep executed: accumulated test/upgrade-arc-* branches deleted, never-delete set verified intact before and after
- [ ] #3 red/031-rollback-watchdog routed to its owner for one answer
- [ ] #4 Framework change shipped per the ruling: LOCAL harness runs self-delete their branches at end-of-run (exit trap, ARC_NO_PUSH-symmetric), and the weekly image-cleanup workflow gains the 7-day branch-GC backstop; CI teardown untouched
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (relayed by foreman)
created: 2026-07-12 21:41
---
AC#1 RULED (architect, 2026-07-12 night), with two ground-truth corrections to this ticket's framing:

CORRECTION 1 — CI already self-deletes: upgrade-arc-harness.yaml's teardown job (:572-596, if: always()) deletes both test/* branches, recomputing names from run_id so it survives partial failures. The ~100 accumulated branches are the GAPS: runs predating the teardown job, LOCAL harness runs (upgrade-target.sh:484 pushes, nothing local deletes), and teardown misses (cancelled pre-teardown, runner death, local ctrl-C).

CORRECTION 2 — this ticket's "delete once the image digest is recorded" is TOO EARLY: the branch's second job is keeping the commit FETCHABLE — the 082 install.sh --commit path runs `git fetch origin <sha>` on the VMs mid-run, and GitHub only reliably serves fetch-by-SHA for ref-reachable commits. Correct timing = END-OF-RUN (teardown), which CI already does.

THE RULED MECHANISM: (1) PRIMARY — end-of-run self-delete, already shipped in CI; the framework change is extending it to the LOCAL path: delete_throwaway_branches() helper in upgrade-target.sh beside the :484 push (same recompute-from-run-id shape as CI teardown, ARC_NO_PUSH-guarded symmetrically), called from the local harness exit trap. (2) BACKSTOP — a branch-GC step in the EXISTING weekly image-cleanup.yaml (which already owns arc-artifact GC by design): delete test/upgrade-arc-* branches older than 7 days; 7d >> any run duration so age alone suffices, no run-state check; the pattern can never match the never-delete set by construction. (3) ONE-TIME SWEEP — the backstop's own logic run once, dry-run listing first, never-delete set verified before and after. (4) red/031-rollback-watchdog → the STATBUS-035 keep-pending owner walk. Insertion points: upgrade-target.sh:~484, .github/workflows/image-cleanup.yaml; CI teardown untouched.
---

author: mechanic
created: 2026-07-12 22:38
---
DRY-RUN COMPLETE (mechanic, 2026-07-12) — AC#2's one-time sweep, per the architect's ruled 7-day-age logic. `git ls-remote --heads origin` = 116 branches total; 90 match `test/upgrade-arc-*`; never-delete set confirmed present and untouched by the pattern (master, all 11 ops/*/deploy/* pointers, db-seed = 13 refs, verified by exact ref match — none begin with `test/upgrade-arc-`).

FULL FINDING, HONEST: all 90 branches' tip commits date 2026-07-07T04:37:42Z through 2026-07-12T13:24:45Z — every one is WITHIN the last 7 days (cutoff for today's run: 2026-07-05T22:37:33Z). **Zero branches are eligible for deletion under the ruled age-based rule today.** This isn't a sweep failure — the ~100 branches this ticket's ground truth counted on 2026-07-12 are the SAME 90 I see now, all freshly created by this week's intense arc-testing campaign (U1-U12 kill-family sweep, wave 8-10 health-park, etc.) — none is old enough yet to qualify as dead cruft under the 7-day bound the architect set (`7d >> any run duration`). Full dated list: tmp/statbus-165-dry-run-list.txt (kept).

No deletions performed (nothing qualified). The never-delete set needs no 'after' re-verification since nothing was touched. AC#2 is effectively satisfied as a no-op today — the sweep logic is proven correct (ran, listed, filtered, found 0), and the population WILL start aging past 7 days from 2026-07-14 onward, at which point the weekly image-cleanup.yaml GC backstop (AC#4, in progress) picks them up automatically without a second manual sweep.
---

author: foreman
created: 2026-07-12 22:40
---
SWEEP EXECUTED (AC#2) + GC BACKSTOP SHIPPED (mechanic built, foreman reviewed + committed ed25061c1). Sweep outcome, honest: ZERO branches eligible — all 90 test/upgrade-arc-* tips date 2026-07-07ℓ2026-07-12, inside the ruled 7-day bound (dry-run list tmp/statbus-165-dry-run-list.txt + comment #2; never-delete 13 refs verified present and structurally unmatchable). The ~100-branch count this ticket opened against is entirely this week's arc-campaign debris, not aged cruft; the weekly branch-gc job (dry-run on manual dispatch, real delete on cron, prefix-guarded per destructive call, fail-loud on refusals) picks it up automatically from 2026-07-14. Remaining: AC#4's local-harness half (delete_throwaway_branches() in upgrade-target.sh — HELD while arc re-runs are in flight tonight) and AC#3's owner routing of red/031-rollback-watchdog (the 035 keep-pending walk).
---
<!-- COMMENTS:END -->
