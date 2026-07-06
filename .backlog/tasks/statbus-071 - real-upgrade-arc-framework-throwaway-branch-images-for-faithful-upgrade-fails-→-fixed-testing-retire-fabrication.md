---
id: STATBUS-071
title: >-
  real-upgrade-arc-framework: throwaway-branch images for faithful "upgrade
  fails → fixed" testing (retire fabrication)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-17 09:05'
updated_date: '2026-07-06 15:59'
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

**One of those crash points is itself a safety feature — the rollback heartbeat (formerly STATBUS-031).** If the *undo itself* hangs — the database-restore stalls partway through a rollback — a heartbeat keeps the box alive and restarts it sanely until the undo finishes, instead of freezing or dying in an endless restart-loop. The heartbeat **code already shipped** (commit a8279ed83). The **test** proving it lives here: deliberately stall the restore — with the heartbeat the box stays alive and reaches `rolled_back`; without it (a build with the heartbeat removed) it restart-loops. STATBUS-031 is folded into this ticket — its code is done, its test is this arc.

## Coverage map — every way an upgrade can break, its exact test, whether it's proven
*Living checklist. Tags: [PROVEN] green on a real VM · [IN FLIGHT] building/observing now · [TODO] not built yet · [ASSESS] no clean trigger yet.*

**The migration itself goes wrong**
- Errors out -> `failing-arc` (real migration that `RAISE`s) -> rolls back, DB logically == old, fix applies fresh — **[PROVEN]**
- Was broken but already succeeded here (the many) -> `working-arc` -> box accepts the fix, re-stamps, no re-run — **[PROVEN]**
- Runs slow but keeps progressing -> `postswap-migration-timeout-arc` (`migration-slower-than-systemd-unit-timeout`) -> heartbeat keeps the box alive -> finishes — **[PROVEN]**
- Runs past the hard ceiling -> aborted -> rolls back — **[TODO] STATBUS-095**
- Eats all memory -> OS kills it -> rolls back — **[TODO] STATBUS-096**

**Killed mid-upgrade, BEFORE booting the new binary -> roll back to old**
- During the code checkout -> `preswap-checkout-kill-arc` — **[PROVEN]**
- Mid-backup -> `preswap-backup-kill-arc` — **[PROVEN]**
- At the binary-swap moment -> `preswap-binary-swap-kill-arc` — **[PROVEN]**

**...AFTER booting the new binary**
- During the post-swap restart -> `postswap-container-restart-kill-arc` -> rolls back — **[PROVEN]**
- Just after a migration commits, before it's recorded (parent killed) -> `postswap-after-commit-kill-arc` -> unrecorded migration -> rolls back, not forward — **[IN FLIGHT]** built+wired (doc-017), confirming VM-proven
- Same instant, the migrate sub-process killed -> `after-commit-before-recorded-kill-arc` -> rolls back — **[IN FLIGHT]** built+wired (doc-017), confirming VM-proven
- Mid-migration / between migrations / mid-transaction -> arcs being built (5d) -> forward-recovery, finishes — **[IN FLIGHT]**

**The undo (rollback) itself is hit**
- Killed during the rollback -> `rollback-kill-arc` (deterministic -> the built-in rollback) -> rolled back — **[PROVEN]**
- The rollback's DB-restore HANGS (the heartbeat, formerly STATBUS-031) -> `postswap-rollback-restore-watchdog-arc` (`restore-db-stall-watchdog`) -> heartbeat keeps the box alive -> rolled back; without it, it restart-loops — **[IN FLIGHT]** observing now -> then asserts (5c-hard)

**A step just stalls (slow, not killed) -> the heartbeat must keep the box alive -> finish**
- DB reconnect stalls after a restart -> `postswap-watchdog-reconnect-arc` — **[PROVEN]**
- Archive-backup stalls -> `postswap-archivebackup-watchdog-arc` — **[PROVEN]**

**Scheduling edge**
- Daemon claims a scheduled upgrade with no live signal -> `claim-without-notify-arc` (STATBUS-098) -> claims + finishes — **[PROVEN]**

**No clean trigger yet**
- Two migrations deadlock on a schema lock -> `3-postswap-worker-ddl-deadlock` (still a scenario) -> may need a product change — **[ASSESS]**

**Done-criterion:** every cell runs through the real register+schedule path; the last fabrication (`fabricate_scheduled_upgrade_row`) is deleted at zero callers (5e).

(Subsumes the now-closed STATBUS-091 "phase-2 charter", STATBUS-075 "cut-rc04 campaign", STATBUS-061 "preswap-recovery", STATBUS-031 "rollback heartbeat", STATBUS-102 "intentional-fix bless" (rename + amendments.tsv rip-out + channel-bless all shipped; the end-to-end bless-proof + the genuine-broken-fix fixture reframe are the working arc here), and STATBUS-099 "legacy-scenario-sweep" (the product-impossible deletes happen inside the kill-family reshape, 5d) — their remaining work is this framework and its arcs. Full run-by-run build history in this task's git log.)
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
- 5c-hard: the ROLLBACK HEARTBEAT test (formerly STATBUS-031). Deliberately stall the rollback's database-restore (exec.go:761): with the heartbeat the box stays alive -> rolled_back; without it (RED = 79375b9f9) it restart-loops. Heartbeat code already shipped (a8279ed83); finish the observational arc to ASSERT; the broken standalone scenario (scenarios/4-rollback-restore-watchdog.sh) is retired (its harness can't drive a real failure). Closes the former 031.
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

author: foreman
created: 2026-07-03 10:47
---
INHERITED PROOF OBLIGATIONS (from the King-ratified consolidation's Cluster-6 verify-closes, 2026-07-03) — these three tasks closed on code evidence; their RUN-proof obligations transfer HERE, to be discharged as the reshaped scenario/arc suite goes green: (1) from STATBUS-084: the 4 no-host-compiler install scenarios (backup/binary-swap/checkout/4-rollback-kill freshness reds) green via sbimage.Procure — the scenarios couldn't run anyway until the controlled-B reshape (slices 3-4) lands; (2) from STATBUS-112: upgrade + rollback unaffected by the archiveBackup removal (the tar was never the rollback artifact — any green arc discharges this); (3) from STATBUS-113: the scheduled-backup behaviors on a real box (fires on cadence, SKIPS during service- and install-driven upgrades, catches up after downtime, purge keeps N, failure never crashes the service). Also standing from today: the working+failing arc re-run after the 110 exemption fix = 110's AC 1-3 + 118's DoD + 109's behavioral oracle.
---

author: engineer (board sweep)
created: 2026-07-06 15:59
---
FOLDED IN from STATBUS-013 (merged 2026-07-06): 071's coverage map carries the after-commit arcs asserting rolled_back and cites 013. 013's King-ratified spec (a crash in the commit↔record gap MUST end rolled_back) is NOT superseded; its canonical spec+verify home is STATBUS-105, its arc coverage lives here.
---

author: engineer (board sweep)
created: 2026-07-06 15:59
---
FOLDED IN from STATBUS-094 (merged 2026-07-06): two small arc-harness-hardening items for 071's residual list — 094's own text already said 'addressed in the 071 hardening pass'.
---

author: engineer (board sweep)
created: 2026-07-06 15:59
---
FOLDED IN from STATBUS-101 (merged 2026-07-06): a ~10-line self-validating RED-gate option for one of 071's arcs — belongs on the same hardening list.
---
<!-- COMMENTS:END -->
