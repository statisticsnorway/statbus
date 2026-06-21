---
id: STATBUS-071
title: >-
  real-upgrade-arc-framework: throwaway-branch images for faithful "upgrade
  fails → fixed" testing (retire fabrication)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-17 09:05'
updated_date: '2026-06-21 19:27'
labels:
  - install-recovery
  - upgrade
  - testing-foundation
  - architect-plan
  - doctrine
dependencies: []
documentation:
  - doc-012
priority: high
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
Prove, on real machines, that a StatBus box **installs -> upgrades -> hits a broken migration (or not) -> fixes itself -> upgrades again**, data intact, **entirely on its own**. That is Albania: a box inside a statistics office with no remote access — its only upgrade path is a local operator clicking "upgrade" in the web UI, after which the box applies and recovers autonomously, with no one to SSH in if it breaks. Passing this barrage earns the confidence to cut a release (the candidate also runs against the **large Norway database**, to catch slow/runaway migrations a small DB never reveals).

## The issue
We could not faithfully test "an upgrade breaks, a fix lands, the box recovers." The old tests **faked** the failure — a hand-written `public.upgrade` row + an injected kill — which never goes through the real schedule -> service -> apply machinery. A faked failure proves nothing about the real recovery.

## The solution
Drive **real upgrades between throwaway git branches** on real VMs, through the **exact operator path** — no fabrication:
- Off a base commit **A**, make two throwaway branches: **B** = A + the migration under test; **C** = B with that migration **corrected in place** (same file, fixed bytes — not a new migration on top). Pushing them builds per-commit images.
- Four CI jobs on a fresh Hetzner VM: **construct** (the branches + images) -> **image-wait** -> **run-arc** -> **teardown**.
- run-arc: install **A** + demo data -> `./sb upgrade register/schedule <B>` (writes the `public.upgrade` row; a DB trigger wakes the upgrade service, which claims + applies on its own) -> watch `public.upgrade.state` reach `completed` / `failed` / `rolled_back` -> same for **C**. No SSH, no deploy branch — exactly Albania's path.

V's number = highest existing migration + 1 (so it sorts after A's and is genuinely *pending*). The working V creates `public.upgrade_arc_fixture(id,note)` and inserts `(1,'arc')`, so the test confirms V actually ran.

## The rule the arc relies on (fixing a broken migration)
A released migration is immutable; the **only** legitimate reason to change one is to fix a genuinely broken one (crashed / timed-out / OOM) — declared at the release cut, enforced by the gate. A box then handles the fix **by upgrade channel** (STATBUS-106): a developer's box -> **error** (a human is present); the edge box -> **re-run** (data loss fine — dev runs the newest commit daily); a real release box -> **accept the fix**: re-stamp the record *without* re-running. Safe because a broken-fix changes only *whether* the migration finishes, never *what* it produces; trust is earned by the gate. Never destroy data on a real box.

## The two stories the arc proves
**1 — A broken migration that already ran (the many).** It succeeded for small-DB hosts; the fix ships; a real box **accepts the fix** — re-stamps without re-running. [GREEN on a real VM]

**2 — An upgrade fails, rolls back clean, the fix applies fresh (the few).** A real migration fails one of three ways -> the box rolls itself back -> **after rollback the DB is logically identical to A** (schema + ledger + data, compared via a *normalized* dump) -> C applies the corrected V fresh and completes, data intact. That logical-identity-after-rollback is the property **no faked test can prove.** [error-failure GREEN; timeout + OOM modes = STATBUS-095 / 096]

| How V fails | Kill source | Test trigger |
|---|---|---|
| Plain error | none | `RAISE EXCEPTION` |
| Stall -> timeout -> aborted | internal (our 12 h ceiling, seconds in test) | V announces, sleeps; the ceiling fires |
| OOM-killed | external (OS kills Postgres) | V announces, sleeps; a listener confirms mid-run, then kills Postgres |

## The same flow, crashed at other points (the kill family)
The test also injects a **real** crash/stall at the other upgrade points — fetching code, the pre-upgrade backup, the binary swap, between migrations, just-after-a-migration-commits-before-it's-recorded, during the rollback, and while restarting — and checks the box recovers on its own. All run through the real register + schedule path. The after-commit-before-recorded kill's correct recovery terminal is **`rolled_back`** (STATBUS-013, the King's verbatim spec — restore to known-good, operator retries). The only fabrication left to delete is `fabricate_scheduled_upgrade_row` (it only made `./sb install` dispatch; 086's register + schedule produces that row for real).

## Status
- [GREEN] Working arc (accept-the-fix / re-stamp) — on a real VM.
- [GREEN] Failing arc (error -> rollback -> logically-identical-to-A -> fix applies fresh) — the framework's unique value.
- [IN PROGRESS] Kill family reshaped onto the real register + schedule path: CAT-A done; CAT-B / CAT-C in progress.
- [TODO] Timeout-kill + OOM-kill modes (STATBUS-095 / 096); the after-commit-before-recorded kill (terminal = rolled_back per STATBUS-013).
- [DONE-CRITERION] `fabricate_scheduled_upgrade_row` deleted at zero callers; no synthetic crash-state anywhere.

(Folds in former STATBUS-091 "phase-2 charter" and STATBUS-075 "cut-rc04 campaign," now closed — their live remainder was this framework. Full run-by-run build history in this task's git log.)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 WORKING arc GREEN on a real VM: install A → B applies migration V → C re-stamps V's content_hash autonomously; data intact; zero orphan branches/VMs
- [x] #2 FAILING arc GREEN on a real VM: install A → B's V deliberately fails → box rolls back to 'rolled_back' → clean-slate fingerprint equals the post-A baseline → C applies the fix fresh; data intact
- [ ] #3 Kill-family scenarios reshaped: the FABRICATED scheduled-upgrade row replaced by a real register+schedule (086); the crash stays real (existing inject / external NOTIFY-handshake kill)
- [ ] #4 fabricate_scheduled_upgrade_row DELETED with zero callers; NO synthetic crash-state fabrication remains anywhere (King's no-residual rule)
- [ ] #5 STRETCH (product-pristine): in-migration-SQL inject hooks retired in favour of the NOTIFY-handshake + external-kill-timing where feasible; remaining hooks limited to the Go-internal windows that no SQL can reach, each justified
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
STATUS (2026-06-21): both arcs GREEN on real VMs — working/accept-the-fix (run 27807092720) + failing/clean-slate-after-rollback (run 27811604893, the framework's unique value). Kill family being reshaped onto the real register+schedule path: CAT-A done; CAT-B/CAT-C in progress.

DISPATCH (remaining work — doc-016 is the engineer-ready plan):
- 5c-hard: rollback-restore-watchdog re-scoped to a real V_fail trigger at restoreDatabase's stall site (exec.go:761).
- 5d: CAT-C mid-tx kill (:202) + after-commit kill (:844/:845, terminal = rolled_back per STATBUS-013), each VM-proven; DELETE deterministic-error + checkout-kill-legacy; ASSESS worker-ddl-deadlock.
- 5e: shared-fixture matrix (one dispatch, all scenarios parallel) -> DELETE fabricate_scheduled_upgrade_row at zero callers (AC#4 = done-criterion).
- Plus STATBUS-095/096 (timeout + OOM failure modes).

FOLDED IN (2026-06-21, King-directed): STATBUS-091 (phase-2 charter — Waves 1+2 complete: 086 CLI verbs, 072 amend-conveyance, 087/088/089/090 fixes all landed) + STATBUS-075 (cut-rc04 campaign — install RC v2026.06.0-rc.04 cut). Both CLOSED; their only live remainder was this framework.

Designs: doc-012 (build-spec), doc-016 (kill-arc reshape plan, §9(5) implementable). Full run-by-run build history (every commit + VM run, the bug-by-bug hardening) preserved in this task's git history.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-06-21 19:27
---
▶ 5c-hard DISPATCHED to engineer 2026-06-21 (King-directed via architect; architect reviews post-build). Scope tightened after grounding the tree against doc-016 (06-19):

ONE BUILD ITEM — re-scope test/install-recovery/scenarios/4-rollback-restore-watchdog.sh + arcs/postswap-rollback-restore-watchdog-arc.sh from the death-during-resume (Resuming-latch) trigger to a V_fail trigger (failing migration at postSwap → postSwapFailure → rollback() → real restoreDatabase → stall via restore-db-stall-watchdog @ exec.go:761 → active-phase WatchdogSec ticker → rolled_back, NRestarts baseline, data intact). Reuse failing-arc.sh's V_fail fixture. WHY: STATBUS-067 self-heal (resumePostSwap :5053) defeats the old Resuming-latch trigger.

GROUNDING (verified, supersedes doc-016 5c-hard's fuller text):
- doc-016's 5c-hard DELETES ARE ALREADY DONE: resume-died-rollback, archivebackup-resume scenarios + arc_install_kill_dropin helper are ABSENT. 5c-hard = the re-scope only.
- 5d delete-targets (3-postswap-migration-deterministic-error, 2-preswap-checkout-kill-legacy) + CAT-C scenarios (mid-tx-kill, migrate-killed-after-commit) still exist — confirm 5d is the next unit.
- restore-db-stall-watchdog inject confirmed exec.go:761 + inject.go:249.

FLAGGED TO ARCHITECT (3): (1) deletes-already-done; (2) STATBUS-031 RED branch red/031-rollback-watchdog@79375b9f9 is now STALE — cut to RED the OLD Resuming-latch trigger; V_fail re-scope needs RED-delta re-validation; (3) ticket overlap 031 (watchdog code, landed a8279ed83) vs 071/5c-hard (scenario re-scope) — awaiting architect/King call on whether this scenario's home folds 031→071. Engineer building; report routes to architect for review before foreman commit + VM-prove.
---
<!-- COMMENTS:END -->
