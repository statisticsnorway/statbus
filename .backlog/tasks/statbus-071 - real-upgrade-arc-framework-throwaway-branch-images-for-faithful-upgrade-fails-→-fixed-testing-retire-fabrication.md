---
id: STATBUS-071
title: >-
  real-upgrade-arc-framework: throwaway-branch images for faithful "upgrade
  fails → fixed" testing (retire fabrication)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-17 09:05'
updated_date: '2026-07-15 08:30'
labels:
  - install-recovery
  - upgrade
  - testing-foundation
  - architect-plan
  - doctrine
dependencies: []
documentation:
  - doc-012
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: prove on real machines that a box installs → upgrades → breaks → fixes itself autonomously — the contract StatBus makes with every country's statistical office that installs it.
> BENEFIT: the confidence to cut a release comes from a barrage instead of hope — every recovery claim in the coverage map is run-proven, and the last fabrication (the test lying about how state arose) is deleted.
> STAGE: Testing foundation for Stage 1; its coverage map is the checklist the stable gate reads.
> COMPLEXITY: mixed — engineer builds the kill-family arcs and fabrication deletion; mechanic rebuilds individual scenarios; architect reviews; VM runs are the oracle. Absorbs 094+101 hardening items.
> DEPENDS ON: nothing — it is the foundation others wait on.

---

## North Star
Prove, on real machines, that a StatBus box **installs -> upgrades -> hits a broken migration (or not) -> fixes itself -> upgrades again**, data intact, **entirely on its own**. This is the contract with ANY country's national statistical office that installs StatBus: a box inside the statistics office, no remote access assumed — its only upgrade path is a local operator clicking "upgrade" in the web UI, after which the box applies and recovers autonomously, with no one to SSH in if it breaks. Passing this barrage earns the confidence to cut a release (the candidate also runs against the **large Norway database**, to catch slow/runaway migrations a small DB never reveals).

## The issue
We could not faithfully test "an upgrade breaks, a fix lands, the box recovers." The old tests **faked** the failure — a hand-written `public.upgrade` row + an injected kill — which never goes through the real schedule -> service -> apply machinery. A faked failure proves nothing about the real recovery.

## The solution
Drive **real upgrades between throwaway git branches** on real VMs, through the **exact operator path** — no fabrication:
- Off a base commit **A**, make two throwaway branches: **B** = A + the migration under test; **C** = B with that migration **corrected in place** (same file, fixed bytes — not a new migration on top). Pushing them builds per-commit images.
- Four CI jobs on a fresh Hetzner VM: **construct** (the branches + images) -> **image-wait** -> **run-arc** -> **teardown**.
- run-arc: install **A** + demo data -> `./sb upgrade register/schedule <B>` (writes the `public.upgrade` row; a DB trigger wakes the upgrade service, which claims + applies on its own) -> watch `public.upgrade.state` reach `completed` / `failed` / `rolled_back` -> same for **C**. No SSH, no deploy branch — exactly the path the statistical office's operator walks.

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
- Runs past the hard ceiling -> killed by our own 12h bound (`STATBUS_MIGRATE_UP_TIMEOUT`, seconds in test) -> `postswap-migration-ceiling-arc` -> rolled back, orphan backend reaped, clean slate — **[PROVEN]** run 28842366163 (STATBUS-095 closed on it)
- Eats all memory -> OS kills Postgres ONCE -> `postswap-migration-oom-arc` — **[PROVEN]** run 28955342618 — `rolled_back` (V_sleep unrecorded, clean-slate fingerprint matches A). The King's original "rolls back" wording is now LITERALLY true, proven on a real VM under STATBUS-145's atomicity flip: the delta runs exactly once, inside applyPostSwap's guarded migrate step; a mid-delta OOM kill reads observed-state positively Behind on the very next live pass → one-shot snapshot restore, never a forward re-attempt. The single/recurring-OOM split question is SUPERSEDED by STATBUS-145 — mid-delta OOM → Behind → rolled_back is structural, not a live open question.

**Killed mid-upgrade, BEFORE booting the new binary -> roll back to old**
- During the code checkout -> `preswap-checkout-kill-arc` — **[PROVEN]**
- Mid-backup -> `preswap-backup-kill-arc` — **[PROVEN]**
- At the binary-swap moment -> `preswap-binary-swap-kill-arc` — **[PROVEN]**

**...AFTER booting the new binary**
- During the post-swap restart -> `postswap-container-restart-kill-arc` -> rolls back — **[PROVEN]**
- Just after a migration commits, before it's recorded (parent killed) -> `postswap-after-commit-kill-arc` -> unrecorded migration -> rolls back, not forward — **[PROVEN]** run 28832014634 (the STATBUS-105 measurement: rolled_back, per the King's ratified rule)
- Same instant, the migrate sub-process killed -> `after-commit-before-recorded-kill-arc` -> rolls back — **[PROVEN]** run 28832014634
- mid-tx (parent-kill in the commit↔record gap, the STATBUS-105 measurement): **[PROVEN]** completed (forward), run 28980487041 — the tree-SIGKILL lands on a PRE-DELTA tx: V1 is parked mid-transaction inside the crash-recovery's own floor-bound boot-migrate (`--to DaemonSchemaFloor`), not inside the delta step. The aborted tx surfaces as boot-migrate's own failure (exit 137) → STATBUS-017 defer (a service-held flag is present) → RecoverFromFlag's PostSwap-phase arm fires (captured live: `Resuming upgrade 2 (7b567e36) where it left off, now running the new version.`) → post_swap re-runs fresh → the delta (V1+V2) applies cleanly → `completed`. `recovery_attempts=2` is CORRECT BY DESIGN, not a race artifact: the crash-ladder's own detection pass counts 1, the arc's explicit second (recovery) dispatch counts 2 — deaths = attempts−1 = the one kill this arc performs. The daemon-race construction bug that disqualified the wave-2 run is fixed (daemon re-confirmed stopped before each dispatch) and the same arithmetic reproduced cleanly here. The kill never reached the delta itself — this is a PRE-delta-death, same family as mid-migration below.
- mid-migration (parent-kill before the first migration even starts): **[PROVEN]** completed (forward), run 28980487041 — the one-shot KillHere fires inside the crash-recovery's own floor-bound boot-migrate (`--to DaemonSchemaFloor`), which then fails (exit 137). Captured live: `crash recovery: boot migrate up failed but a service-held flag is present (id=2, phase="post_swap") — deferring to RecoverFromFlag (STATBUS-017): exit status 137`. RecoverFromFlag runs post_swap forward from there, applying the delta (V1+V2) fresh; `recovery_attempts=1` (single actor, single pass — no second dispatch in this arc). Same PRE-delta-death family as mid-tx above — the kill never reached the delta step (applyPostSwap's own migrate call) at all.
- between-migrations (parent-kill between the two migrations): **[PROVEN]** rolled_back, run 28976918080 — subprocess kill lands AFTER V1 records (MID-delta: the ledger has already advanced, the delta step itself was reached and interrupted) → postSwapFailure's observed-state read finds it positively Behind on the first read → one-shot rollback → os.Exit(75); ledger reverted to baseline, clean-slate fingerprint matched A. This is the MID-delta-death representative — the opposite half of the ruled rule from its two PRE-delta-death siblings directly above (mid-tx, mid-migration), which both prove forward/completed instead. THE RULED RULE (all three runs together): a migrate-window death BEFORE the delta starts (floor no-op boot-migrate, or an aborted pre-delta tx) → STATBUS-017 defer / post_swap forward → delta applies fresh → `completed`. A death MID-delta with the ledger already advanced → observed-state Behind → one-shot rollback → `rolled_back`. Both are designed behavior, not bugs.
- [ASSESS] mid-V1-during-the-resume's-own-delta-application (ledger still at baseline, but the kill lands INSIDE applyPostSwap's guarded migrate step itself, not the floor no-op that precedes it): no run exists for this exact window. By the same ruled rule (ledger unmoved + the delta step itself interrupted → Behind → rollback, same shape as between-migrations) the derivation says `rolled_back` — but this is an ASSESS note, not an assertion. A dedicated variant arc is built only on the King's ask.

**The undo (rollback) itself is hit**
- Killed during the rollback -> `rollback-kill-arc` (deterministic -> the built-in rollback) -> rolled back — **[PROVEN]**
- The rollback's DB-restore HANGS (the heartbeat, formerly STATBUS-031) -> `postswap-rollback-restore-watchdog-arc` (`restore-db-stall-watchdog`) -> heartbeat keeps the box alive -> rolled back; without it, it restart-loops — **[PROVEN]** run 28837119781 (cover HOLDS: NRestarts frozen through the stalled restore, clean rolled_back, byte-identical clean slate)
- The rollback DIES twice in a row (process death, not hang) -> `rollback-pair-terminal-arc` -> restore-broke terminal (state='failed', human summoned) at EXACTLY 2 consecutive rollback deaths, never a third attempt (STATBUS-134's bound) — **[PROVEN]** run 28839994287
- The rollback's git restore is CORRUPT (catastrophic abort) -> the ABORT terminal write (state='failed' + error, flag removed — STATBUS-136) is now proven for REAL by the `restore-broke-reattempt` arc below — **[PROVEN]** run 29344519124 (2026-07-14). The former `4-rollback-abort-write-lands` scenario that fabricated this is RETIRED on this half; MAP CORRECTION (architect, STATBUS-071 comments #16/#17, 2026-07-14 — supersedes this row's prior single-deletion note): that scenario's OTHER half — the SAME box's flagless self-heal to `completed` (STATBUS-039, `completeInProgressUpgrade`) — is NOT provable by the arc (its git corruption is real and permanent, so it never self-heals) and is NOT dead-producer-eligible (comment #12), so it survives narrowed + renamed as the scenario `4-flagless-selfheal-at-target` — **[UNPROVEN, interim-netted]**, standing only until a real-path successor (a real dispatched upgrade stalled post-swap, then a real flag-file truncation on the VM) goes green. Its sibling `4-rollback-abort-churn-then-alive-idle` (STATBUS-144 AC#3's flagless-churn-then-alive-idle net) is uncoupled from the same deletion note and stands separately, also interim-netted pending its own real-path successor — **[UNPROVEN, interim-netted]**. Both interim nets are named `fabricate_resume_state` callers alongside the sole dead-producer member `3-postswap-rune-wedge`, per the King's carve-out ruling (comment #12).
- The operator RE-ATTEMPTS a broken restore (`./sb install` on a restore-broke box, state='failed' + retained backup_path) -> restore-broke-reattempt arc -> DUAL-CLASS oracle, both classes REQUIRED: (i) pair-terminal row class — the re-attempt runs (watchdog armed, git-state guard first, db stop, shared restore) -> restore completes -> the row reaches its honest `rolled_back` terminal; (ii) abort row class with STILL-CORRUPT git — the re-attempt REFUSES actionably (ErrRollbackGitCorrupt) BEFORE any destructive step, naming the corruption and the operator's next step: never a mixed-era box, no silent wedge, no crash loop — **[PROVEN]** run 29344519124 (2026-07-14; obligation moved here from STATBUS-111 at its close, architect-ruled 2026-07-12; design pins in STATBUS-111 comment 1 / final summary). THIS ARC ALSO CARRIES the abort-terminal WRITE-LANDS oracle (architect ruling, 2026-07-12): its abort-row construction — real dispatch of a broken-migration B, post-swap kill, then corrupting the restore inputs on the VM (environment manipulation of real machinery state, not fabricated rows) — produces exactly the state `4-rollback-abort-write-lands` used to fabricate; folded that scenario's ABORT assert (terminal lands in ONE pass: state='failed' + error together, flag removed) into this arc's spec, proven on the same run. See the row above for the corrected disposition of that scenario's surviving self-heal half (narrowed, not deleted) and its churn sibling.
- The operator UN-PARKS after fixing the cause IN PLACE (the park banner's own advertised remedy: "fix the cause, then re-trigger") -> un-park-to-completion arc -> a RESOURCE-class park where the fix is genuinely external, re-scoped (architect ruling, 2026-07-14) into its two proven-or-provable arms: (i) DELTA upgrades + resource failure -> rollback + re-trigger (the timed fill, diskPrecheckReason, the Behind-confirmed one-shot restore, and the full-disk rollback path) — **[PROVEN]** run 29360596950; (ii) NO-DELTA (codeonly) upgrades + resource failure -> the box parks AT-TARGET on the disk shortfall (disk-named park reason, exactly one STATBUS_EVENT=parked siren, alive-idle through the RestartSec settle, zero rollbacks in `public.upgrade_state_log` at park AND completion), the operator frees the disk, `./sb install` grants exactly ONE fresh attempt, the SAME row completes with ZERO restores anywhere and data intact — **[PROVEN]** run 29367295181, commit e9b3d3bb0 (2026-07-14). Both arms run-proven; the two-arm row is now fully **[PROVEN]**.

**A step just stalls (slow, not killed) -> the heartbeat must keep the box alive -> finish**
- DB reconnect stalls after a restart -> `postswap-watchdog-reconnect-arc` — **[PROVEN]**
- Archive-backup stalls -> `postswap-archivebackup-watchdog-arc` — **[PROVEN]**

**The new version can't serve its users (health) -> park alive-idle, wait for the fix**
- Health gate refuses a can't-serve version -> `postswap-health-park-arc` (doc-029) -> parks at-target with the named health reason, sirens exactly once per park event, parked-skip boots stay alive-idle, deliberate un-park grants one fresh attempt, re-park with fresh reason + second siren, daemon ACTIVE after re-park, and a genuine fix release DISPLACES the standing park (B superseded with its story intact) and completes with data intact — **[PROVEN]** run 29171998401 (2026-07-12, wave 10 — the arc's first full end-to-end green; waves 1-9 each caught a real product bug en route: STATBUS-148 health gate, STATBUS-154 teardown race + invisible writer, STATBUS-147 daemon-down, STATBUS-159 parked-blocks-claim). This IS the real-path park proof under the STATBUS-145 geometry (doc-028's reclassification): the r19 fabricated park scenario was the interim net and is now due for deletion, with fabricate_resume_state dropping to its ONE sanctioned dead-producer caller (rune-wedge) per the King's carve-out ruling.
- A fix release FAILS and rolls back onto the DISPLACED version's binary (B parked -> C claims, displacing B to superseded -> C fails post-swap -> rollback puts the box on B) -> C-rollback resurrection leg -> the box boots + the operator runs `./sb install`: B STAYS superseded (no resurrection through any door — the deleted reconciler, the narrowed install upsert, the terminal-resurrection DB trigger), C stays rolled_back, the state log shows NO terminal-to-completed transition, and the refuse names the re-dispatch remedy — **[PROVEN]** run 29380351572, commit dc3e6786b (run 4 of the arc): parked-B displaced by C at claim (story intact in error via the atomic park write), C's failing V3 rolled back onto B with HEAD reconciled, install resurrects nothing through any door, truth told (box runs B, no completed-B ledger row, honest 400 on the rest bind), guard-probe refusal with the row byte-unchanged. (architect ruling on STATBUS-160, 2026-07-12: 'completed' means THIS VERSION VERIFIABLY SERVES — only serve-proven writers may write it; the running-but-unrecorded version is an observed fact via system_info, never a ledger edit)

**A recovery step hits a TRANSIENT error (db blip, missing commit) -> quiet in-process backoff, never exit-restart noise**
- The DB dies TRANSIENTLY mid-recovery (killed and revived while a recovery pass runs) -> transient-db-backoff leg -> the backoff-retry dispatch (STATBUS-109, shipped 782ca2455) retries quietly in-process with the wall-clock connect probe, resolves when the DB returns, recovery completes — no unit exit, no restart-counter noise; the exhaust arm (DB never returns) routes to the classify-then-act disposition — **[PROVEN]** run 29393095941, commit f17528214 (run 4 of the arc, 2026-07-15): both arms end-to-end on one run. EXHAUST: at-Behind crash base → stall → paused-DB hang classified as CauseDBUnreachable (the STATBUS-190 bounded reads) → in-process backoff engaged → budget exhausted → the rollback stopped the paused container itself, restored, rolled_back with the cause named, NRestarts bounded, data intact. RESOLVES: the NEW at-target crash base (killed-by-system-after-migrations-before-completion) → stall → pause → backoff engaged → unpause within budget → cleared → re-read AlreadyAtNew → FORWARD COMPLETION (state=completed), flag gone, no orphan backup, healthy, data intact. Four runs, three real findings en route: the images-ready harness precondition (caught in the wild by STATBUS-187's #3 hard-fail), the hang-shaped-unreachable product gap (STATBUS-190, fixed + live-proven), and the false arm-1 unpause premise (run-disproven, removed). WITH THIS, THE COVERAGE MAP'S RELEASE-GATING REMAINDER IS EMPTY — every release-gating row is [PROVEN] or honestly [RETIRED] with invariants cited.
- The target COMMIT is not yet fetchable mid-recovery -> commit-not-fetched-backoff leg -> **[RETIRED — structurally unreachable, architect-ruled 2026-07-15, engineer-traced]**: the CauseCommitNotFetched DISPATCH arm is DELETED (commit a9029a103; the classify-then-act switch, service.go). The cause is impossible at the resuming verify, proven by three invariants: (1) the ONLY dispatch caller is the Phase=NewSbUpgrading classify-then-act; (2) a NewSbUpgrading flag exists only AFTER executeUpgrade's pre-swap fetch → the object is local by construction of the phase (service.go:1893); (3) the recovery-boot checkout gate (service.go:1903) runs `git checkout flag.CommitSHA` and FAILS the boot on a missing object. The CLASSIFIER stays whole (service.go:2545 still names the cause) → with the arm gone the cause falls to the default human-stop WITH THE CAUSE NAMED (loud, actionable, zero retry of a structurally-impossible state). fetchWithStallDetection KEPT (live forward-fetch caller, service.go:5398); commitNotFetchedSpec deleted as orphaned. Surviving unit oracle: TestVerifyBinaryObservedState_TargetMissingFromCloneIsUnknown (classifier names the cause) + TestCommitNotFetchedDispatch_Retired (no dispatch arm → default human-stops naming the cause). The db-unreachable leg stays LIVE + **[UNPROVEN]** — its arc rides the stalled-before-resuming-verify hook.

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
> STATUS (2026-07-15, supersedes the 2026-07-12 recap; prior dispatch history in this file's git log): THE RELEASE-GATING REMAINDER IS EMPTY — every coverage-map row above is [PROVEN] on a real VM or RETIRED with a written ruling. Tonight's closers: restore-broke-reattempt (run 29344519124, dual-class incl. the folded ABORT oracle), un-park-to-completion both arms (delta→rollback run 29360596950; no-delta park→un-park→completed on the codeonly lineage), C-rollback resurrection (guard-probe + honest broken-B end state), transient-db-backoff both arms (hang-class via docker pause, post-STATBUS-190 bounded reads), commit-not-fetched RETIRED (structurally dead at the resuming verify — three code-cited invariants; the classifier + named human stop remain, unit-pinned), ddl-deadlock assessed (R1 quiesce already shipped on both paths — scenario refresh + one bounded run when prioritized, non-gating).
>
> WHAT REMAINS ON THIS TICKET (tail, none release-gating):
> 1. Flagless-selfheal real-path successor — narrowed interim scenario stands; successor arc uses the killed-by-system-after-migrations-before-completion site + flag truncation (run 2 in flight).
> 2. Churn-scenario real-path successor (144 AC#3's interim net stands until it goes green).
> 3. AC#4's zero-callers end state: fabricate_resume_state down to the sanctioned dead-producer caller (rune-wedge) once both successors land; fabricate_scheduled_upgrade_row still has live arc callers (AC#4's other half).
> 4. AC#5 stretch unchanged.
>
> The coverage map above is the authoritative living state; the Implementation-Notes history that used to live here (U-campaign dispatches, X/Y resolution, carve-out ruling chronology) is preserved in git history and the comment thread.
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

author: architect
created: 2026-07-07 00:56
---
U1 LEDGER (run 28832014634 on c525de51c, 2026-07-07 — first live contact for five kill arcs; architect diagnosis from the CI logs, tmp/u1-failed-logs.txt). ALL FIVE ARCS RED — and ZERO of the reds are product findings. Two harness bug families explain everything:

FAMILY 1 — STALE-PID KILL MISS (after-commit-before-recorded, postswap-after-commit, postswap-mid-tx). The hard part WORKED: the torn window was genuinely constructed — the logs show the stall engaged with the fixture table committed and db.migration still at baseline (V applied but unrecorded), exactly the commit↔record gap. Then the SIGKILL hit "No such process": the target PID had been captured BEFORE the exit-42 handoff respawned the process. And the arcs' cleanup then removed the stall's release file — un-parking the stalled migrate, whose very next statement was the ledger INSERT — so the migration became fully applied AND recorded and the upgrade finished normally. 'completed' was the CORRECT terminal for what physically happened; the arc had (unknowingly) cancelled its own experiment. mid-tx variant: park worked, parent-kill missed, only the migrate subprocess died, and the SURVIVING parent's own rollback (stopping the DB) made the arc's probe read a transport error as a wrong-state verdict.

FAMILY 2 — ASSERTION SEQUENCING (between-migrations, mid-migration). The product story in these logs is EXEMPLARY: the inject kill fired mid-migration, the next pass detected crashed-upgrade, ran the SIGKILL-class quiesce, the still-armed inject killed the boot-migrate too and STATBUS-017's defer handled it, recovery resumed forward and reached completed with recovery_attempts=1 and the flag removed. The arc then asserted "flag present after the kill" — after its own install helper had already driven that entire recovery inside one step. Wrong assertion placement, right product.

FIXES DISPATCHED (foreman): one shared kill helper ending the stale-PID class (fresh PID at kill time, kill, poll-until-gone; IRON RULE: never touch the release file unless the kill is CONFIRMED — releasing after a miss is what manufactured the false 'completed'); transport-aware state probes (a psql failure is never a state verdict); split the install-helper contract so the RED midpoint is asserted between kill and recovery.

OBSERVED LIVE IN THE U1 LOGS (coverage-map annotations — seen working, NOT yet arc-green; cells flip [PROVEN] only on the fixed re-run): crashed-upgrade ladder detection · SIGKILL-class quiesce (the "never SIGTERM" line, live) · STATBUS-017 boot-migrate defer (a killed boot-migrate deferring to flag recovery) · budget-hoist attempt counting (exactly 1 attempt for one deliberate recovery) · completed self-heal · the completion-write reconnect save (the 047-H stale-connection retry, firing and succeeding twice).

THE STATBUS-105 STATEMENT, plainly: the torn-migration measurement has NOT happened yet. Every 'completed' ever observed on this path — including the overnight observation that opened 105 — is explained by the harness miss above (a released stall finishing its bookkeeping legitimately). The King's rolled_back rule is UNTESTED live, not violated. The fixed re-run of the two after-commit arcs IS the 105 measurement.
---

author: foreman
created: 2026-07-07 02:59
---
KILL-FAMILY SWEEP COMPLETE (2026-07-07): run 28832014634 (after-commit ×2 + mid-tx GREEN — the 105 measurement; 105 closed on it) + run 28837119781 (between-migrations + mid-migration + rollback-restore-watchdog ALL GREEN). SIX cells flip [IN FLIGHT]→[PROVEN]: the two after-commit torn-window arcs (rolled_back per the ratified rule), mid-tx, the two migration-window arcs (reshaped to the product's real promise: in-dispatch forward recovery — kill lands, dispatch survives via the deferred-recovery path, completed at attempts==1), and the rollback-restore-watchdog cover-HOLDS arc (NRestarts frozen through a stalled restore → clean rolled_back with byte-identical clean slate; U2 proven). Harness classes ended en route: stale-PID kill miss + release-after-miss (the confirmed-kill helper, 4b6da9fdd), the transport self-match (bracket idiom), the hold-end assertion contradiction. NEW product tickets from the campaign's scenario legs: STATBUS-143 (probe-vs-connect route mismatch in install recovery) and STATBUS-144 (flagless post-terminal boot-migrate churn). Rune-wedge GREEN (044 AC#1 checked); abort oracle one cleanup-fix from green with the 136 property already run-proven. Remaining U-campaign: abort oracle round 3, pair-terminal arc run (after this sweep — lineage now confirmed green), U5 legacy deletions, U6/AC#4 gated on the King's carve-out ruling.
---

author: foreman
created: 2026-07-07 03:46
---
ABORT ORACLE GREEN (round 4, 2026-07-07, HEAD 089860e65, local VM run): 4-rollback-abort-write-lands PASSED end-to-end as a DUAL oracle — (1) the STATBUS-136 property from the early single-snapshot read: ABORT terminal landed complete in ONE pass, zero kills (state='failed' + full ROLLBACK_FAILED_GIT_CORRUPT error together, flag removed, exactly one callback, NRestarts==1); (2) promoted round-3 finding: the SAME boot's flagless rune-class self-heal (STATBUS-039, ground-truth-gated markCurrentVersionCompleted) then converged the fabricated at-target row to completed/error-NULL — now a deliberate live-proven assertion, not a surprise. Round ledger: r2 red = flagless churn (→ filed STATBUS-144 + cleanup step); r3 red = late error read raced the self-heal (→ combined same-snapshot reads on both sides of the RestartSec boundary). Audit rider recorded on the 014 family: the self-heal NULLs the error trail (failed→completed). PAIR-TERMINAL ARC status: first real run (28838952364) proved the CONSTRUCTION works line-by-line (pre-swap route, kill inside rollback, recordRollbackCommit stamp fired) but the arc's flag reader was compact-JSON-only while the product writes MarshalIndent — one-line space-tolerant reader fix shipped (b0df2af0d), re-dispatched as run 28839994287.
---

author: foreman
created: 2026-07-07 04:01
---
PAIR-TERMINAL ARC GREEN (run 28839994287, HEAD b0df2af0d, 2026-07-07) — U4a PROVEN on a real VM: the pre-swap route construction (C5 → PreSwap → recoveryRollback → C9 kill inside rollback), TWO in-process kills with the recordRollbackCommit stamp now READ correctly (death 1: step='rollback' prior=''; death 2: same-step pair), and the STATBUS-134 pair-terminal bound fired at EXACTLY 2 consecutive rollback deaths → restore-broke terminal. All jobs green (construct / image-wait / run-arc / teardown / reap). With the abort oracle green (comment #8), BOTH U4 oracles are now run-proven. Remaining U-campaign: U5 legacy deletions (engineer sweep in flight — pair-terminal-gated holds now lifted), U6/AC#4 gated on the King's carve-out ruling, plus the 095/096 TODO cells.
---

author: foreman
created: 2026-07-07 04:05
---
U5 COMPLETE (4a5d45913, 2026-07-07): 11 legacy scenarios DELETED, each with a named run-proven arc replacement (preswap backup/binary-swap/checkout, container-restart, migration-timeout, watchdog-reconnect, 4-rollback-kill → their long-proven arcs; after-commit-subprocess + mid-tx → run 28832014634; between-migrations + mid-migration → run 28837119781). Assertion set-difference checked per deletion; architect spot-check (between-migrations) found the arc's contract STRICTLY EXCEEDS the deleted scenario's. Scenario count 30→19, README rows → supersession notes naming arc + C-class + proving run. doc-016's named 5d targets were already absent (verified). KEPT: 3-postswap-migrate-killed-after-commit (known-RED, off-gate) per the architect's ruling. RESIDUAL (architect's exact wording): 'Add the clean-slate fingerprint assert to postswap-after-commit-kill-arc ON ITS NEXT NATURAL CI DISPATCH — never a dedicated run — then delete 3-postswap-migrate-killed-after-commit; the error-string residue is explicitly waived (fabrication artifact).' 5e stays correctly gated on the King's carve-out ruling — fabricate helper retains real callers (preswap backup/checkout arcs + kept scenarios). U-campaign remaining: 095/096 TODO cells, ddl-deadlock ASSESS, U6/AC#4 (King-gated), the fingerprint-assert residual above.
---

author: architect
created: 2026-07-08 13:34
---
THE WRITTEN UNREACHABILITY PROOF the sharpened carve-out rule requires is on the board as **doc-028** (architect, 2026-07-08, fresh adversarial trace — the King asked to see the sequence in detail to judge unrepresentability). THE HONEST OUTCOME SPLITS THE CLASS: (1) RUNE-WEDGE — proof HOLDS, structurally: the natural producers are two FIXED bugs (the Apr 24 SDNOTIFY-collision abort, service.go:6002-6004; the step-11 proxy gap, :5461-5464); the fixed product cannot COMPOSE 'forward flag present + full container set running-stale' on any path (every mid-pipeline path has the app set stopped at :4773 or recreated-at-target at :5460+); and every approximation self-converges within one RestartSec=30s window, so persistence requires suppressing the unit — interference that destroys the takeover-of-a-live-unit subject itself. Construction is the honest substitute for a state whose producer we deliberately killed. (2) PARK/boot-migrate — proof FAILS today: the arc framework reaches the same state ON CUE through real dispatch (construct B = A + V_sleep → real register/schedule → real claim → exit-42 handoff → STATBUS-060's recovery checkout delivers V_sleep as pending → boot-migrate hangs → confirmed-midpoint daemon kill ×2 → same-step-twice park), every piece run-proven in adjacent arcs (OOM run 28841893851, mid-migration run 28837119781). The r12 impossibility was true of the OLD construction (delta on disk BEFORE dispatch → boot consumed it) and does not transfer to the arc path where the delta arrives only via the flag-gated post-handoff checkout. (3) STATBUS-145 interaction: if ratified, mid-delta deaths read Behind → one-shot rollback (Phase=resuming stamped at service.go:253/6255), so the park-at-boot-migrate subject dissolves for delta migrations and the park scenario must be rebuilt regardless — rebuild ONCE, as a real-path arc on 145's geometry, keeping the r19-green fabricated version as the interim net. ASKS (doc-028 §end): narrow the carve-out to DEAD-PRODUCER STATES (sole member: rune-wedge); reclassify the park scenario as real-path-reachable with its arc rebuild riding the 145 build; fabricate_resume_state then keeps exactly one sanctioned caller. AC#4's zero-callers gate updates accordingly if the King ratifies the narrowed rule.
---

author: foreman
created: 2026-07-08 13:46
---
KING RULED the carve-out (2026-07-08): the doc-028 split verdict stands, and the run-cost objection is DISMISSED as a category error — his words: the cost that matters is 'me having to travel to another country with plane in the middle of Africa... because we failed to address this issue', not CI minutes. RULING: construction permitted ONLY for DEAD-PRODUCER states (a state whose natural producer is a bug we deliberately fixed — written proof required, consumed by the real recovery reader in the run); sole member today: the rune-wedge scenario. fabricate_resume_state keeps exactly ONE sanctioned caller. The park scenario is reclassified REACHABLE — its real-path rebuild rides the STATBUS-145 geometry (under atomicity the park-at-boot-migrate subject dissolves for delta migrations); the r19-green fabricated version stays ONLY as the interim net and is deleted when the rebuild goes green. AC#4's zero-callers criterion is amended accordingly: zero callers outside the dead-producer class. STANDING DOCTRINE from the same ruling (recorded in team memory): decisions are pre-filtered through the production-reality frame — a question that dissolves in that frame does not reach the King.
---

author: foreman (relaying King)
created: 2026-07-14 10:04
---
KING RULED (2026-07-14): drive the remaining arcs NOW, one by one — the foundation is NOT adequate as-is, it blocks the release train. His words: 'we only find the real errors when we run the real operations. Everything else is just wishful thinking.' Dispatch order: (1) restore-broke-reattempt arc (mechanic building now — release-gate checklist row from 111), then (2) un-park-to-completion, (3) C-rollback resurrection leg, (4) the two transient-backoff legs, ddl-deadlock [ASSESS] last (may need a product change ruling). Each arc: build → foreman commit+push → CI VM run is the oracle → map row flips [PROVEN] only on green.
---

author: foreman
created: 2026-07-14 10:50
---
RESTORE-BROKE-REATTEMPT run 1 (29325230294) RED — HARNESS SEQUENCING, PRODUCT EXEMPLARY: the pair-terminal construction worked end-to-end (C5 wedge, two rollback deaths, (rollback,rollback) pair, terminal in one pass: failed + ROLLBACK_FAILED_DB_RESTORE + backup_path retained), and then the arc's 4th dispatch — copied from the pre-111 pair-terminal arc as a 'terminal stays stable' check — actually RAN THE RE-ATTEMPT (post-STATBUS-111, ./sb install on failed+backup_path routes to StateRestoreReattemptable) and completed the restore to rolled_back, exit 0. Phase (i)'s intended proof happened one dispatch early; the assert expected the obsolete pre-111 stability semantics. Fix dispatched (mechanic, after his 168 freeze): the post-terminal dispatch IS the re-attempt — move the rolled_back/fingerprint asserts onto it, drop the duplicate 5th; ALSO audit rollback-pair-terminal-arc's own tail for the same latent post-111 assumption, and explain the 10:41:23 unit boot-migrate failure in the journal before re-dispatch.
---

author: foreman
created: 2026-07-14 15:41
---
RESTORE-BROKE-REATTEMPT ROW FLIPS [PROVEN] — run 29344519124 GREEN (2026-07-14, run 5 of the arc; runs 1-4 each peeled a real layer: post-111 dispatch semantics ×2, a dead-window DB read, checked-out-branch deletion). PROVEN in one run: (i) pair-terminal row → the SAME dispatch's STATBUS-111 re-attempt → honest rolled_back, byte-identical clean slate, attempts=3 surviving the rewind (STATBUS-181); (ii) REAL git-corrupt ABORT (V_fail × C9 parent-kill × detached branch deletion — environment manipulation of real machinery state, zero fabrication) → state=failed + ROLLBACK_FAILED_GIT_CORRUPT + backup_path retained + attempts=1 in ONE pass (the folded 4-rollback-abort-write-lands oracle) → the re-attempt REFUSES actionably before any destructive step, row untouched. FOLLOW-UP UNIT now due per the map row's own note (the r19 pattern): DELETE scenario 4-rollback-abort-write-lands and drop fabricate_resume_state to its ONE sanctioned dead-producer caller (rune-wedge) — queued to the mechanic; that lands AC#4's amended zero-callers criterion. Remaining map rows after this: un-park-to-completion, C-rollback resurrection leg, the two transient-backoff legs, ddl-deadlock [ASSESS].
---

author: architect
created: 2026-07-14 16:06
---
R19-PATTERN DELETION RULED (architect, 2026-07-14; the mechanic's U5 set-difference catch was right — the map's deletion note was incomplete; nothing gets deleted as originally noted). No King needed: test-suite shape inside the blessed campaign structure — no product behavior, no permission machinery, no release-gate change.

1. 4-rollback-abort-write-lands → NARROW, do not delete (option a). The ABORT write-lands half retires (arc-proven, run 29344519124). The surviving oracle — the STATBUS-039 flagless self-heal — is completeInProgressUpgrade (service.go:2776), and its VALUE is boot ROUTING plus the routine's guard set: the 135 parked-skip (:2793-2810), the defer flag-strip semantics, and observed-state verification before 'completed'. Only a real service boot on a real box exercises that; a DSN-level Go test would prove the UPDATE and miss the routing — option (b) rejected as primary (and go-test has no cluster; 182 just settled where DB-needing Go tests live — new machinery for a weaker oracle). Option (c) rejected: a zero-coverage 039 safety behavior is not a gap to accept when narrowing is cheap.

FABRICATION LEGITIMACY (dead-producer doctrine): the fabricated [flagless + in_progress row + at-target] state has NAMED live producers — (i) the corrupt-flag removal path: recoverFromFlag unmarshal error → os.Remove, row untouched (service.go:898-901; verified in code today); (ii) the exit-42 self-update restart window the routine's own call-site comment documents (:2233-2235); (iii) tmp/ flag-file loss across reboot. The narrowed scenario's header MUST cite these producers — a fabrication without a named producer is a phantom test.

NARROWING MECHANICS: rename to the surviving oracle (suggest 4-flagless-selfheal-at-target). NB the rename moves the per-scenario stamp key — the narrowed scenario needs its own fresh green run to stamp; honest, it IS a new scenario. KEEP: fabricate at-target in_progress row + NO flag → next boot converges state='completed', error NULL, LabelCompletedFromInProgress in the log, no flag on disk. DROP: everything ABORT-related including the phase-patch sed to 'resuming' — the self-heal half is flagless by definition and never needed it. Do NOT extend the scenario to the parked-skip branch (one canonical oracle per behavior; if 135's branch lacks coverage that is its own question, noted, not smuggled in here).

2. 4-rollback-abort-churn-then-alive-idle → KEEP STANDING, uncouple. It is 144 AC#3's only regression net (flagless churn → StartLimit → alive-idle), untouched by the new arc. Header rewritten now: the joint-deletion claim removed, standing alone as the 144 AC#3 net, remaining a legitimate fabricate_resume_state caller (producers = 144's own documented exit-20 genre). The misleading 4-rollback-abort- name prefix: rename ONLY when the scenario is next re-run anyway (a rename re-keys its stamp); header-only today.

3. fabricate_scheduled_upgrade_row: concur with the foreman — 5 live callers, AC#4's other half, no action now.

MAP CORRECTION: the coverage-map deletion note is superseded by this ruling — ABORT cell → the arc; flagless-self-heal cell → the narrowed scenario; churn cell → the standing scenario. Mechanic updates the map rows with this comment as the source.
---

author: architect
created: 2026-07-14 16:07
---
CORRECTION TO COMMENT #16 (architect, 2026-07-14, self-caught on re-read against the King's ratified carve-out) — my "fabrication legitimacy" paragraph INVERTED the doctrine and is WITHDRAWN. Comment #12's ruling is explicit: construction is permitted ONLY for DEAD-PRODUCER states, and fabricate_resume_state keeps exactly ONE sanctioned caller (rune-wedge). I argued the self-heal fabrication was legitimate BECAUSE live producers exist — backwards: live producers mean the state is REACHABLE, and reachable states must be produced by the real path (the park reclassification is the precedent). The dispositions correct to:

1. 4-rollback-abort-write-lands → still NARROW to the flagless-self-heal oracle (everything in #16 about the oracle's value, the kept/dropped asserts, the rename + stamp re-key, and rejecting options (b)/(c) STANDS) — but the narrowed fabricated scenario is the INTERIM NET ONLY, exactly like the park interim was: it stands until a REAL-PATH successor goes green, then deletes. The real-path construction is available in the blessed genre (environment manipulation of real machinery state, per the run-29344519124 ABORT precedent): a real dispatched upgrade stalled at a known post-swap point, then TRUNCATE the flag file on the VM → the real corrupt-flag reader removes it (service.go:898-901) → the next real boot's completeInProgressUpgrade converges the row. Queued as a map row [UNPROVEN, interim-netted]; not release-gating.
2. 4-rollback-abort-churn-then-alive-idle → same correction: KEEP standing + uncouple (as #16 ruled), but as the INTERIM NET for 144 AC#3 — the churn state's producer is live (144 was discovered in a real occurrence, r2 of the abort-oracle rounds), so a real-path rebuild is owed and queued as a map row; the fabricated version deletes when it goes green.
3. AC#4's amended criterion is UNCHANGED and remains the end state: zero fabricate_resume_state callers outside the dead-producer class (sole member rune-wedge). The two interim nets are NAMED exceptions with explicit deletion conditions — the same standing the park interim had under the King's own ruling, so this correction fits inside the ratified doctrine and still needs no new King decision.

Mechanic's immediate work is unchanged by the correction: narrow + rename the self-heal scenario (with the interim-net framing in its header, producers cited as REACHABILITY evidence not legitimacy), uncouple the churn header, update the map (ABORT cell → arc [PROVEN]; self-heal + churn cells → interim-netted [UNPROVEN] rows naming their real-path successors).
---

author: mechanic
created: 2026-07-14 16:24
---
Coverage-map rows updated per architect comments #16/#17 (direct edit to the description's Coverage map section — its ~20k chars exceed this tool's description-field cap, so the map itself was edited with a file-level tool; this comment is the MCP-visible pointer). Changes: (1) the ABORT-catastrophic-restore row now reads [PROVEN] run 29344519124, crediting the restore-broke-reattempt arc, with the map's prior single-deletion note replaced by the corrected disposition — the former 4-rollback-abort-write-lands scenario is RETIRED only on its ABORT half; its flagless-self-heal half survives narrowed+renamed as 4-flagless-selfheal-at-target [UNPROVEN, interim-netted]; its churn sibling 4-rollback-abort-churn-then-alive-idle stands uncoupled, also [UNPROVEN, interim-netted]. (2) the restore-broke-reattempt row flips [UNPROVEN]→[PROVEN] run 29344519124 (was stale — comment #263 already recorded the green run but the map row hadn't been flipped). Build side: 4-rollback-abort-write-lands.sh deleted; 4-flagless-selfheal-at-target.sh created (fabricates an at-target in_progress row with NO flag, asserts the flagless self-heal to completed/error-NULL via completeInProgressUpgrade, producers cited as reachability evidence per comment #17's correction); 4-rollback-abort-churn-then-alive-idle.sh header uncoupled from the stale joint-deletion claim, now framed as its own interim net. test/install-recovery/README.md rows updated to match. Frozen for foreman review, not committed.
---

author: foreman
created: 2026-07-14 17:34
---
INTERIM-NET FIRST GREEN (2026-07-14 evening): 4-flagless-selfheal-at-target (the narrowed rename of 4-rollback-abort-write-lands' surviving oracle) PASSED its required fresh run — install-recovery-harness run 29353418547, dispatched via CI after two LOCAL attempts died to VM SSH drops (rc=255 mid-bootstrap / mid-install — infra, not asserts; a third local attempt earlier died to the STATBUS-184 tip-race). The flagless self-heal (orphan at-target in_progress row → next ordinary boot → completeInProgressUpgrade → completed/error-NULL, [completed-from-in-progress] in the journal, no flag ever, NRestarts≤1, data intact) is proven on a real box under the narrowed scenario's own name. The STATBUS-039 coverage the set-difference check protected is intact and freshly stamped.
---

author: architect
created: 2026-07-14 17:45
---
DDL-DEADLOCK CELL ASSESSED (architect, 2026-07-14) — the last [ASSESS] row, now decision-ready. HEADLINE: the product change the cell was waiting on ALREADY SHIPPED; the scenario's "no fix exists" premise is stale; one bounded VM run flips the cell [PROVEN].

(1) WHAT THE SCENARIO CONSTRUCTS (3-postswap-worker-ddl-deadlock, read in full): a real install at a pinned baseline + demo data + a CONTINUOUS worker workload (statistical_history_reduce enqueued every 2s — AccessShareLock held seconds at a time on history tables) + `./sb install` at HEAD applying the real migration delta. Zero fabrication — this is the jo/tcc forensics wedge's exact shape: an operator install over a live, loaded box. Real-path reachable under the 145 geometry: YES — the install step-table's Migrations step is deliberately apply-all (145 bounded only the crash-recovery boot-migrate).

(2) TRIGGER DETERMINISM: the GREEN direction (the regression net) is deterministic — with the quiesce in place, completion does not depend on winning any lock race; the workload proves the quiesce beats a genuinely-busy worker. The RED direction (observing the wedge) is per-lock nondeterministic AND would require un-fixing the product — pointless; the wedge is forensics-documented history, not a claim needing re-proof.

(3) THE PRODUCT CHANGE: SHIPPED, both paths, verified today — the scenario header (written at 1f077e545) predates it.
- INSTALL PATH: the R1 quiesce window is wired into the step loop (cli/cmd/install.go:633-680): compose.QuiesceClients stops worker/app/rest before Seed/Migrations whenever those steps actually need to run, HARD-FAILS if the quiesce fails ("must not proceed with DDL on live services"), and ResumeClients restarts exactly the stopped set after the window closes (compose.go:126/:158); db/proxy stay up throughout.
- UPGRADE PATH: Step 3 stops app/worker/rest before backup/swap (service.go:5190-5193); the delta then runs on the new binary with clients still down, services returning only after migrate + health.
- Boot-time floor catch-up on a live box is a no-op on any healthy box (floor migrations long applied); recovery boots run with clients down. Residual, out of the cell's scope: a freehand `./sb migrate up` by an operator on a live box — operator action outside the machinery's promise.

(4) KING FRAMING — one recommendation: RUN-THE-SCENARIO. Not fix-the-product (done); not retire-the-cell (one bounded run converts the map's last question mark into proof on the exact forensics wedge, and the scenario's own activation condition — "activates the moment the R1 fix is ready" — is met). Pre-run refresh, small (mechanic): rewrite the stale header (fix landed, cite install.go:633-680 + service.go:5190), re-pin INSTALL_VERSION to a recent baseline so the delta is realistic, keep the existing pass criteria (terminal within the 15-min budget, data intact, counts match snapshot, NRestarts ≤ 2). Cost: one VM, bounded. On green the cell flips [PROVEN] and the coverage map carries no [ASSESS] rows.
---

author: foreman
created: 2026-07-14 18:18
---
DDL-DEADLOCK [ASSESS] ROW RESOLVED GREEN (2026-07-14 evening, local harness run tmp/ddl-deadlock-run2.log — PASS, 35 checks): the refreshed scenario (regression net for the shipped R1 quiesce, baseline re-pinned to rc.05) ran a real upgrade over a live loaded box with the continuous worker workload and completed cleanly — the quiesce-before-DDL fix holds under the exact jo/tcc wedge shape. Run 1 en route fixed dormant harness staleness: the workload helpers predated the VM_EXEC multi-line guard (converted to VM_SCRIPT_INLINE; also fixed stop's wait-cap reading the VM name as its bound). The coverage map now carries ZERO [ASSESS] rows; remaining [UNPROVEN]: un-park-to-completion (rebuilt on the two-check timed-fill construction, run pending), C-rollback resurrection leg, the two transient-backoff legs — plus AC#4's zero-callers end state (interim-net successors queued).
---

author: architect
created: 2026-07-14 19:47
---
UN-PARK ARC RUN-2 RULED (architect, 2026-07-14; run 29360596950): option (a) WITH (c)'s crediting folded in — the map row re-scopes to the 145-era truth and the no-migration lineage variant gets built. The red is not a defect anywhere: it is the classify-then-act doctrine executing verbatim, and it proved something on the way.

1. THE DESIRED-STORY QUESTION, answered plainly: YES — rollback-on-full-disk is the RIGHT operator story for a delta-carrying upgrade, and the run proved it clean end-to-end. Positively-Behind + deterministic resource failure ⇒ a data-safe restore is AVAILABLE, and taking it hands the NSO operator a SERVING box at the old version plus an actionable remedy ("free disk space, then re-trigger" — a fresh schedule retries; displacement handles the rest). Parking instead would hold a non-serving mixed state (new binary, behind DB) alive-idle for no benefit. The park exists precisely for the states where rollback is UNSAFE or UNDECIDABLE: at-target (restoring would destroy post-upgrade writes) and unverifiable. The map row as written was chasing a state the product deliberately — and correctly — avoids for delta upgrades.
2. WHERE THE RESOURCE PARK GENUINELY LIVES: no-migration upgrades. A code-only release (B = A + code change, no V) is at-target by construction at the pre-pull check (ledger max == on-disk max; binary post-swap = target) → a deterministic resource failure there routes to PARK (parkForDeterministicFailure's at-or-past-target arm, verified this session). This is not a synthetic class — code-only releases are a normal fleet reality (app/CLI-only RCs). The honest construction: the small construct-lineage variant that builds B WITHOUT V; fill disk post-swap pre-pull → park (alive-idle + siren) → free disk → `./sb install` un-parks → the SAME row's fresh attempt completes. That is exactly the row's original story, now on the reachable class.
3. MAP ROW RE-SCOPE (the (c) half): the row splits into its two proven-or-provable truths — (i) DELTA upgrades + resource failure: rollback + re-trigger, PROVEN by run 29360596950 (credit it: the timed fill, diskPrecheckReason, the Behind-confirmed one-shot restore, and the full-disk rollback path are all now run-proven — record on the row); (ii) NO-DELTA upgrades + resource failure: the resource-class PARK + genuinely-external fix + un-park-to-completion — [UNPROVEN], the variant build's oracle.
4. BUILD: yes — mechanic or engineer builds the no-migration lineage variant (foreman's dispatch call). Scope is small: a construct-lineage flag/variant that skips V; the cross-version arc already proved non-constructed targets flow, so only the harness's always-adds-V assumption moves. The arc's assert set for arm (ii): park reason names the disk (diskPrecheckReason text), siren exactly once, parked-skip boots alive-idle, un-park grants ONE fresh attempt, row completes, no restore anywhere in arm (ii) (nothing to restore — at-target all along).

Doctrinal footnote for the map: this is the second time a park-row construction moved because of 145 (doc-028 reclassified the boot-migrate park the same way). The general law, worth stating once on the row: UNDER 145's ATOMICITY, PARK IS AN AT-TARGET/UNVERIFIABLE PHENOMENON; anything positively-Behind rolls back. Constructions chasing a park must therefore hold the ledger at-target — which for pre-delta failure sites means no-delta lineages.
---

author: foreman
created: 2026-07-14 20:25
---
ARM-SPLIT UNIT COMMITTED + DISPATCHED (foreman, 2026-07-14 evening): commit 2d5cc0de7 — the codeonly (no-delta) lineage variant (SPEC codeonly in lib/upgrade-target.sh: B = A + non-migration marker, NO V, single-phase like oom/ceiling), the un-park-to-completion arc rewritten to arm (ii) with the architect's full assert set (disk-named park reason, siren exactly once via the health-park UPGRADE_CALLBACK file pattern, alive-idle after the RestartSec settle, zero rollbacks in public.upgrade_state_log at park AND completion, exactly one UN-PARKED grant, same row completes, data intact), and the harness workflow wired end-to-end (9 fixture branches). Arm (i) delta→rollback is credited to run 29360596950 in the arc header; this arc asserts nothing for it. Engineer built per the ruling; foreman reviewed line-by-line and independently verified the schema/event/helper premises. ORACLE IN FLIGHT: arc-harness run 29365576531, operator watching — the map row flips [PROVEN] only on green.
---

author: foreman
created: 2026-07-14 20:44
---
UN-PARK ARM-(ii) RUN 1 RED — BUT THE STORY LANDED (run 29365576531, 2026-07-14 evening, log tmp/unpark-arm2-run1-failure.log): the codeonly lineage reached the resource park exactly as ruled — disk-named park (state-log: in_progress parked=t), siren-once AT the park, alive-idle, zero rollbacks at park AND completion, ./sb install un-parked with exactly ONE grant (inline dispatch app-name confirmed in state-log record 4), same row completed attempts=1, data intact. ONE assert tripped: siren count 3 at completion (expected 1) — the two extra callback-log lines are the COMPLETION callback (normal Slack-OK) and a SECOND callback from the post-upgrade install fixup ('already recorded… no change'), i.e. the arc's completion-time assert counts ALL lifecycle events on the shared callback hook instead of only STATBUS_EVENT=parked lines. Foreman's read: arc assert coarseness, product per-doctrine — sent to the architect for adversarial verification per the alarm-reversal rule before any arc edit. Side question also with the architect: is the fixup's duplicate completion-time callback a real double-notification defect (separate ticket if so). Operator's initial 'deleted tag' classification was unrelated discovery noise on upgrade row 1.
---

author: architect
created: 2026-07-14 20:45
---
UN-PARK ARM-(ii) RUN 29365576531 RED — ADVERSARIALLY VERIFIED (architect, 2026-07-14): the foreman's read is CONFIRMED — arc assert bug, product clean end-to-end. Evidence, not concurrence:

Q1 (assert coarseness vs hidden violation): CONFIRMED coarseness. The arc's callback script logs EVERY event unconditionally (`echo "$STATBUS_EVENT …"`, arc :209), and the completion-time assert counts ALL lines (`wc -l`, :425) — but the ruled assert was "the PARK SIREN fires exactly once", i.e. the `parked` EVENT count. The three logged lines are three DIFFERENT events: `parked` (the siren, 20:37:40), the upgrade completion callback, and `install_completed` from runInstallCallback (cli/cmd/install.go:2601 — verified in code, with the STATBUS-137 comment "name the event (was firing blank)"). The adversarial alternative — "should lifecycle callbacks not follow the parked event on this hook at all?" — is REFUTED by the product's own design: UPGRADE_CALLBACK is the single lifecycle hook and STATBUS-137 deliberately NAMED every event precisely so consumers filter by STATBUS_EVENT; filter-by-event is the contract, and the arc didn't. FIX (engineer, mechanical): count `grep -c '^parked '` at BOTH checkpoints — the park-time assert (:354) has the same latent wc-l coarseness and only passed because the siren was the sole event at that instant; fix both, not just the red one.

Q2 (the second ping — duplicate-notification defect?): NO TICKET — legitimate, designed, and bounded. The two post-completion lines are two DIFFERENT named events for two different facts: `completed`-class (the upgrade row converged; fired by the inline dispatch) and `install_completed` (the operator's ./sb install run finished; fired by the install step-table's own callback). The double ping occurs ONLY on operator-driven `./sb install` dispatches — where an operator is present by definition; a service-dispatched upgrade (notify → daemon) fires a single completion. A Slack consumer that wants one-ping-per-upgrade filters on STATBUS_EVENT — consumer-side filtering IS the 137 contract, not product surgery.

BOOKKEEPING accepted: state-log record 4's un-park (parked t→f) by the inline dispatch's application_name is consistent with the ONE-grant story — the foreman checked the right thing.

VERDICT: dispatch the two-checkpoint assert fix to the engineer and re-run; everything else in the arm-(ii) assert set already held. On green the row flips [PROVEN] as ruled.
---

author: foreman
created: 2026-07-14 20:51
---
UN-PARK ARM-(ii) RUN 2 DISPATCHED (foreman): assert fix committed as e9b3d3bb0 — both checkpoints now count '^parked ' events via a shared ?-safe helper (never total callback-log lines; STATBUS-137 filter-by-event contract, architect-verified), failure paths dump the full callback log. Re-run: arc-harness run 29367295181, operator watching. On green the map row flips [PROVEN].
---

author: foreman
created: 2026-07-14 21:11
---
UN-PARK-TO-COMPLETION ROW PROVEN — RUN 2 GREEN (run 29367295181, commit e9b3d3bb0, 2026-07-14 evening): the full arm-(ii) story on the codeonly (no-delta) lineage — real code-only upgrade parks AT-TARGET on the disk shortfall (disk-named reason, exactly one STATBUS_EVENT=parked siren, alive-idle through the RestartSec settle, zero rollbacks in the state-log), operator frees the disk, ./sb install grants exactly ONE fresh attempt, the SAME row completes with ZERO restores anywhere and data intact. Arm (i) (delta→rollback + re-trigger) stands credited to run 29360596950. The two-arm map row is now fully [PROVEN]. Remaining [UNPROVEN] rows: C-rollback resurrection leg, the two transient-backoff legs, plus the two interim-net real-path successors (flagless-selfheal, churn) — non-release-gating per the doctrine notes. Mechanic flips the map row + README; engineer proceeds to the C-rollback resurrection leg per the King's dispatch order.
---

author: architect
created: 2026-07-14 22:07
---
C-ROLLBACK RESURRECTION LEG RULED (architect, 2026-07-15; both ambiguities, engineer builds immediately). The construction itself is APPROVED as designed — healthpark lineage, C displaces then fails and rolls back, box lands on B, ./sb install — and his install-path verification (StateNothingScheduled authors no row; runInstallSupersede touches only rows older than the running SHA) matches STATBUS-160's narrowed-door design.

AMBIGUITY 1 — OPTION (a), sanctioned as a named genre: GUARD-PROBE. "Try the locked handle, assert it's locked" is NOT fabrication: the fabrication doctrine forbids constructing state the real path cannot produce and then testing recovery ON it — the test lying about how state arose. Here the state (B superseded, C rolled_back) arose via the REAL path end-to-end; the probe ATTEMPTS the forbidden write and is REFUSED — nothing downstream ever consumes probe-produced state, because none is produced. It is the same genre as the house pg_regress constraint tests (SAVEPOINT + expect ERROR, AGENTS.md's own pattern) and as testing a UNIQUE constraint by attempting the duplicate. The no-manual-DB-writes rule governs fixes on deployed boxes; a refused write asserting a guard on a throwaway VM is a test of the guard failing closed. THREE CONDITIONS on the probe: (1) it runs AFTER every real-path assert has completed, so a probe bug can never contaminate the real observation; (2) it asserts BOTH halves — the RAISE text names the re-dispatch remedy AND the row is byte-unchanged after (still superseded, story intact); (3) the arc labels it GUARD-PROBE, visually distinct from the real-path narrative.
- Option (b) REJECTED on the 160 design itself: the ruling says the running-but-unrecorded version is AN OBSERVED FACT VIA SYSTEM_INFO, NEVER A LEDGER EDIT — the materialization must not attempt the write, so there is no journal refusal line to assert; if the daemon ever DID attempt it, that would itself be a defect. Option (c) unnecessary — the map row's "refuse names the re-dispatch remedy" always meant the trigger's RAISE; (a) is its honest reading.
- POSITIVE HALF the leg must also assert (completes the 160 story): the truth is captured somewhere readable — assert the system_info observed-version fact shows B RUNNING while the ledger carries no completed-B row. The doors-closed asserts prove nothing lies; this asserts the truth is still told.

AMBIGUITY 2 — BROKEN-B IS THE INTENDED END STATE, and (i) is verified NO-RED: the install step-table's only health gate is checkServicesDone (cli/cmd/install.go:846), which reads the DB CONTAINER's docker health — postgres is healthy under the healthpark lineage (the break is an app-function RAISE in auth_status, read by the UPGRADE health gate, not by install). So ./sb install completes exit 0 on broken-B — which is exactly right: install refreshes config and papers over NOTHING; it neither fails on nor falsely blesses the broken app. (ii) Broken-B is the truth: C WAS the fix for B's brokenness; C failed and rolled back; the box honestly runs broken B and the remedy is re-dispatching a real fix (C2) — which is the standing healthpark story (a genuine fix displaces and completes, proven in run 29171998401). END-STATE ASSERT SET: box on B's binary; B stays superseded (story intact); C stays rolled_back; state log shows NO terminal→completed transition; install exit 0; system_info observed-version = B; the guard-probe refusal; app health still red (the truth, not a defect). Agreed the disk lineage does not compose — C would hit the same external wall instead of failing on its own content; health is the right lineage.
---

author: foreman
created: 2026-07-14 22:42
---
C-ROLLBACK RESURRECTION ARC COMMITTED + DISPATCHED (foreman, 2026-07-15): commit aeaa6e1ca — new crollback lineage (B byte-identical to healthpark's, C = B + a NEW failing V3; two-phase), the c-rollback-resurrection arc (B parks at-target → C displaces B at claim → C fails post-swap and rolls back onto B → ./sb install resurrects NOTHING: B superseded with story intact, C rolled_back, zero terminal→completed in the state log, install exit 0, box observably runs B via git HEAD with no completed-B ledger row, app health honestly red, data intact — then the architect-sanctioned GUARD-PROBE: attempted superseded→completed refused by the terminal-resurrection trigger naming the re-dispatch remedy, row byte-unchanged), and the harness workflow wired (11 fixture branches). Engineer designed+built per the ruling; foreman verified the trigger text/env plumbing/invocation shapes independently and added the V_VERSION_2/3 fail-fast requires at commit. ORACLE IN FLIGHT: arc-harness run 29373805316, operator watching — the map row flips [PROVEN] only on green. Engineer's honest flag on the run: HEAD==B-after-rollback is the first live exercise of the rollback's tree reconciliation on a C-that-fails — a red THERE is a product finding, with db.migration max==V2 as the independent read.
---

author: foreman
created: 2026-07-14 23:04
---
C-ROLLBACK ARC RUN 1 RED — POSSIBLE PRODUCT FINDING, WITH ARCHITECT (run 29373805316, log tmp/crollback-run1-failure.log): failed at the displacement-narrative assert — after C displaced B, B's error held ONLY ' — displaced by the claim of upgrade id=3' (the note appended to an EMPTY error); the park narrative never lived in error this run. Puzzle: the assert is byte-copied from postswap-health-park, which went GREEN with it on run 29171998401 — same lineage, same break, different error-field outcome. Mechanism candidate from the journal: THIS run's B parked via the RECOVER-FROM-FLAG path (reason written to recovery_parked_reason, error left NULL, unit exit 1), while health-park's green presumably parked inline — i.e. two park writers with different error-field contracts, selection timing-dependent. If confirmed: (a) the displacement story's 'narrative + note both in error' contract silently depends on which writer parked you — an operator/support-story gap; (b) health-park's own assert is latently flaky (no-flaky-tests → must be fixed either way). Architect ruling requested: verify the two-writer hypothesis, rule product-fix vs contract-restatement (both arcs' asserts move together), and explain the inline-vs-recover selection nondeterminism. Everything up to that assert was GREEN: at-target park, reason names B, V1+V2 applied, C displaced B (superseded, marker cleared, one 154 displacement row).
---

author: architect
created: 2026-07-14 23:06
---
C-ROLLBACK RUN 29373805316 RED RULED (architect, 2026-07-15) — REAL PRODUCT FINDING, max-effort verified in code; both runs are explained by ONE mechanism and neither run lied.

(1) THE TWO-WRITER HYPOTHESIS, VERIFIED IN REFINED FORM: there are NOT two park sites — there is exactly ONE (parkForDeterministicFailure → parkUpgrade, the sole `recovery_parked_at = now()` writer, service.go:6484) — but the park is a SPLIT WRITE with two different guarantees. The park columns (parked_at + reason) ride terminalUpdate — the STATBUS-154 teardown-immune channel (context.Background, bounded retry, must outlive the dying pass; parkUpgrade's own doc says so verbatim). The error NARRATIVE rides recordInProgressFailure (:5594) on the PASS's queryConn and the PASS's ctx, with `if d.queryConn == nil { return }` (silent no-op) and a printf-swallowed Exec failure. On health-park's green run the parking pass had a live conn → narrative landed (its assert string is written ONLY at :5594 — grep-verified). On this run the park landed via the recoverFromFlag pass whose conn/ctx was dead or dying at park time → the immune half landed (the arc's parked-reason assert PASSED), the mortal half vanished. This is the EXACT race 154 was built to kill — the fix made the park immune and left its narrative behind. NOT intended; a 154 completeness gap.

(2) PRODUCT FIX SHAPE (rides a product commit before the arc re-runs): fold the narrative INTO the immune write — parkUpgrade's single UPDATE becomes `SET recovery_parked_at = now(), recovery_parked_reason = $2, error = $3 WHERE id = $1 AND state = 'in_progress' AND recovery_parked_at IS NULL` (error value: 'parked on deterministic forward failure: '+reason, today's exact bytes), still via terminalUpdate + upgradeRowReturning; DELETE the :5594 recordInProgressFailure call. One write, one guarantee, atomic — the narrative can never again diverge from the park it narrates. BOUNDED: the only other recordInProgressFailure caller (:5560, the forward-retry transient note) stays best-effort — correct there, it is a live-pass note no terminal story depends on.

(3) DISPLACEMENT CONTRACT: NO restatement needed. With the fix, the narrative deterministically lives in `error` at displacement time, and STATBUS-159's displacement appender composes on top — BOTH arcs' asserts stand AS WRITTEN. Health-park's green becomes deterministic instead of lucky; its latent flake dies with the product fix (no-flaky-tests satisfied by fixing the product, not the assert).

(4) INLINE-vs-RECOVERFROMFLAG ORDERING: genuinely timing-dependent (whether the first pass survives to park in-process or dies at the exit/restart boundary and the next pass parks) and BY DESIGN — recovery is idempotent across passes and no doctrine depends on WHICH pass parks. What must be pass-independent is the ROW'S STORY — exactly what fix (2) restores. Neither arc may pin which pass parks.

CREDIT: the red also run-proved the immune half working (parked reason present on a dying pass) and caught a support-story gap the NSO operator would have hit reading a parked row with an empty error. Builder: mechanic or engineer (foreman's call) — small, one function + one deleted call + a unit test asserting the park UPDATE carries all three columns (structural, same genre as the terminal-write contract test); then the C-rollback arc re-runs UNCHANGED.
---

author: architect
created: 2026-07-14 23:12
---
PARK-FIX SCOPING CONFIRMED (architect, 2026-07-15): PARAMETERIZE — the engineer's premise catch is correct and the gap was mine (I verified parkUpgrade is the sole park WRITER, not that it has a sole CALLER CLASS; three callers: :5590 deterministic, :6424 budget-exhaust, :6825 same-step-twice). Ruling: parkUpgrade(errNarrative string) sets error=$3 inside the same terminalUpdate+RETURNING immune write, for ALL parks — the row's story must be pass-independent regardless of park class. parkForDeterministicFailure passes today's exact bytes ('parked on deterministic forward failure: '+reason; :5594 deleted per the original ruling; both arcs' asserts stand). The budget callers pass their honest narrative — 'parked after N crash-resume attempts: '+reason approved — which closes their EXISTING empty-error support gap for free; option (a) would knowingly preserve for budget parks the exact gap this finding exposed, rejected on the finding's own reasoning. Blanket prefix rejected as mislabeling (concur). One constraint: errNarrative must be non-empty at every caller — a park without a story is a design smell; the structural unit test asserts the three-column UPDATE and non-empty narrative at all three call sites.
---

author: foreman
created: 2026-07-14 23:58
---
C-ROLLBACK RUN 2 RED — NEW PUZZLE, WITH ARCHITECT (run 29376442495, commit a5e8119c0, log tmp/crollback-run2-failure.log): the park-narrative fix PROVED LIVE (displacement asserts all green — narrative + note both in error, one 154 row), and the red moved to the end state: auth_status returned 200 where broken-B must still RAISE. Two findings: (1) LATENT ASSERT BUG regardless — PostgREST maps RAISE/P0001 to HTTP 400 (B's own park reason recorded status=400), so the arc's expected-500 was wrong even for a correctly-broken B; (2) THE PUZZLE — the ledger read db.migration max == V2 (the auth_status-breaking migration) seconds before the probe, yet the function SERVES: something healed auth_status while the ledger kept V2. Candidate mechanisms routed for adversarial verification: wrong-era backup in the migration-failure rollback (would be a serious restored-data-vs-ledger disagreement), a boot/install path re-applying baked function definitions over the restored volume (self-heal doctrine violation if real), or a benign mechanism to be named. Also proven green this run before the red: at-target park, displacement with story intact, C rolled_back with V3 unapplied + HEAD==B (the engineer's flagged first-live-exercise of rollback tree reconciliation PASSED), install exit 0 + no resurrection through any door + no completed-B ledger row.
---

author: architect
created: 2026-07-15 00:09
---
C-ROLLBACK RUN-2 RED RULED (architect, 2026-07-15; max-effort, seven mechanisms eliminated in code+log) — TWO findings, one CONFIRMED and one genuinely UNEXPLAINED; the unexplained one is treated as a potential product finding until named, and the arc must not flip [PROVEN] on any run whose end state cannot be explained.

FINDING 1, CONFIRMED (fix regardless): the assert expects 500; the product's own health gate proves broken auth_status manifests as 400 P0001 through PostgREST (journal 23:51:24-44, url=127.0.0.1:3013/rpc/auth_status, status=400 body P0001). Fix: expect 400 + grep the fixture's P0001 body — the honest broken signature.

FINDING 2, UNEXPLAINED HEAL: at probe time (23:54:35) auth_status EXECUTED SUCCESSFULLY (200) while the ledger read V2 — by both the arc (23:54:08) and THE PRODUCT ITSELF (install preamble 23:54:19: 'DB migration_version 20260714100529 matches on-disk max'). The pair [ledger=V2 + working auth] matches NO reachable state: B-era snapshot = V2+broken (gate 400s at 23:51:44, backup 23:52:23-26 seconds later); A-era = ledger …27 not …29; no-restore = V2+broken (V3's tx rolled back). ELIMINATED WITH EVIDENCE: (1) install refresh — Seed SKIPPED, migrations no-op (its own step output); (2) post_restore.sql — zero auth_status content (55 lines, grepped); (3) db-image entrypoint — config-only params, init-db.sh is first-init only; (4) the proxy's @auth_paths special route — strip_prefix + reverse_proxy to the SAME rest:3000 (standalone.caddyfile.tmpl:101-113); (5) C's migrate re-running a fixed V2 — the delta applied ONLY 20260714100530 (V3, FAILED); the lineage doc confirms V1/V2 stay byte-identical between B and C (upgrade-target.sh crollback section); (6) wrong-era restore — contradicted by the product's own V2 ledger read; (7) restore-never-ran — contradicted by the 9s restore narrative AND would leave broken auth anyway. Something wrote the WORKING function body between 23:53:39 and 23:54:35 without touching db.migration — no known writer fits.

RULING — EMPIRICS BEFORE ANY RE-RUN COUNTS: the engineer adds to the arc, at the probe site AND in _dump_crollback_failure_diagnostics: (a) direct `curl 127.0.0.1:3013/rpc/auth_status` (the product's own route — discriminates proxy-vs-db); (b) `SELECT md5(prosrc) FROM pg_proc WHERE proname='auth_status'` + a grep of prosrc for the fixture RAISE (is the live body broken or original?); (c) db.migration max read THROUGH PostgREST (rules out split-brain reads between psql and rest); (d) a fingerprint of pre-upgrade-active vs the live volume (one known file's checksum — did the restore actually change bytes). Then re-run with the 400-assert fix. If 200 reproduces, the instrumentation names the writer — and whatever silently rewrites database functions after a rollback is a SERIOUS product finding (self-heal doctrine at minimum). If it does not reproduce, the instrumented single-occurrence stands recorded here and the arc proceeds — but no assert gets loosened to 'tolerate 200': the 200 is an unexplained state mutation and no-flaky-tests demands its cause, not its accommodation.

Credit intact from run 2: the park-narrative fix proven live (displacement asserts green), the whole displacement + rollback + no-resurrection + truth-told chain green — only the final honest-broken probe is at issue.
---

author: foreman
created: 2026-07-15 00:41
---
C-ROLLBACK RUN 3: THE PROBES NAMED THE LAYER (run 29378536916, log tmp/crollback-run3-failure.log): the 200 reproduced AND the instrumentation resolved run 2's 'unexplained heal' — THERE WAS NEVER A HEAL. Probe (a) direct rest:3013/rpc/auth_status → HTTP 400 with the fixture's exact P0001 body; probe (b) pg_proc → is_broken_fixture=t; probe (c) fresh-connection ledger → V2; probe (d) C's backup dir intact (2556 files). The DB end state is fully consistent — wrong-era restore, ledger split-brain, and function-rewriter candidates ALL exonerated. The discriminator: the arc's gate probe THROUGH THE PROXY (:3010/rest/rpc/auth_status) gets 200 with an EMPTY body while the rest port tells the truth — the one mechanism the seven-elimination pass had cleared (the proxy's auth_status route) is the one the empirics contradict. With the architect now: (1) name the Caddy mechanism from the generated config (reproducible locally), (2) rule whether a proxy masking a failing auth_status as 200-empty is a product finding (external health monitors would read green on a broken box) or intended auth-route design (the upgrade health gate uses the internal healthURL bind and parked B correctly either way), (3) rule which route the arc's honest broken-B assert should read. Everything else in run 3 was green up to the gate.
---

author: architect
created: 2026-07-15 00:43
---
RUN-3 MECHANISM NAMED (architect, 2026-07-15) — the probes did their job; the 200 is CADDY'S NO-MATCHING-SITE DEFAULT, and there was never a heal.

(1) THE MECHANISM: the arc's probe (plain HTTP, Host: 127.0.0.1, port 3010) matches NO site block in the generated standalone Caddyfile — its only three site keys are `http://{{.Domain}}` (:57), `{{.Domain}}` https (:62), and `http://proxy` (:161, the in-compose middleware host). Caddy v2's documented behavior for a request on a bound listener that matches no site: HTTP 200 with an EMPTY body — which is exactly the observed fingerprint (a genuinely proxied auth_status 200 would carry a JSON body; run 3's was EMPTY). So the @auth_paths route I read in the template is real and honest — the probe simply never reached it: wrong virtual host, not wrong route. CORRECTION TO MY RUN-2 ELIMINATION #4: right conclusion (the auth route doesn't mask), wrong scope — I verified a matching path-route exists, not which SITE the probe's exact request (scheme+Host+port) matches. Transport eliminations must match the request, not the route table.
(2) PRODUCT FINDING? NOT an auth-route defect: the real operator surface (https://SITE_DOMAIN/rest/rpc/auth_status) routes through @auth_paths to rest:3000 and answers the honest 400, and the product's own health gate (internal healthURL, 127.0.0.1:3013) parked B correctly — both unaffected. What IS worth a LOW hardening ticket (foreman files): Caddy's unmatched-host 200-empty means a naive external monitor pointed at a bare IP:port reads GREEN on any box, broken or not — add an explicit catch-all site responding 404 (or 503) for unmatched hosts so no monitor can mistake the void for health. NSO frame: cheap, honest-to-monitors, zero effect on real routes.
(3) THE ARC'S HONEST READ: the broken-B end-state assert moves to the DIRECT rest bind — `curl 127.0.0.1:3013/rpc/auth_status` → expect 400 + the fixture's P0001 body — the same route the product's own gate reads and the DB truth per run-3's probe (a). This is a MOVE to the honest read, not a loosening: through the real domain the surface would also 400; the loopback-host proxy probe was never a representative surface. Cite this mechanism in the assert comment. Keep probes (a)-(d) in the failure diagnostics permanently — they just paid for themselves.

With the 400+body assert on the :3013 route and everything else already green in run 2/3, the next run is expected green and flips the row [PROVEN].
---

author: foreman
created: 2026-07-15 01:19
---
C-ROLLBACK RESURRECTION ROW PROVEN — RUN 4 GREEN (run 29380351572, commit dc3e6786b, 2026-07-15): the full leg end-to-end on the crollback lineage — B parks at-target (health reason naming B, V1+V2 applied), C displaces B at claim (superseded, park narrative + displacement note both in error via the a5e8119c0 atomic park write, one 154 row), C's V3 RAISEs and the daemon rolls C back onto B (V3 unapplied, db.migration at V2, git HEAD reconciled to B — first live proof of rollback tree reconciliation under a failed fix release), ./sb install exits 0 and resurrects NOTHING (B superseded, C rolled_back, zero terminal→completed, no completed-B ledger row, box observably runs B), app health honestly red on the direct rest bind (400 + fixture P0001 body), data intact, and the GUARD-PROBE confirmed the terminal-resurrection trigger refuses naming the re-dispatch remedy with B's row byte-unchanged. FOUR RUNS, THREE REAL FINDINGS ON THE WAY: the split-write park narrative (product fix a5e8119c0, run-proven), the 500-vs-400 assert mapping, and Caddy's unmatched-host 200-empty (hardening ticket STATBUS-189; the operator's 'proxy transformed 400→200' phrasing is corrected here — Caddy never proxied the request at all, it answered its no-matching-site default; fully explained, no further proxy investigation owed). Health-park's displacement assert is retro-hardened by the same product fix. REMAINING release-gating [UNPROVEN] rows: the two transient-backoff legs. Mechanic flips the map row; engineer proceeds to the backoff legs per the King's dispatch order.
---

author: architect
created: 2026-07-15 02:32
---
BACKOFF LEGS RULED (architect, 2026-07-15; four questions).

Q1 — THE HOOK: APPROVED. One new inject stall hook at the top of the Phase=NewSbUpgrading classify-then-act, immediately before verifyUpgradeObservedStateEx. This is exactly AC#5's sanctioned residue — a Go-internal sub-second window no SQL or external timing can reach; the alternatives are window-racing (the U1 stale-PID lesson's forbidden genre) or pre-boot pauses that fail the BOOT connect instead and never reach the branch under test. Name per the house inject vocabulary: `stalled-before-resuming-verify` (KindStall); the site comment carries the AC#5 justification (the window between boot-connect and observed-state verify) + a pointer to this ruling. One hook serves BOTH legs — it holds the world still while the arc arranges the trigger (db pause, or Q2's state), which is what makes both legs deterministic and honest.

Q2 — COMMIT-NOT-FETCHED: NOT YET — REACHABILITY TRACE FIRST (engineer, ~30min, before any construction). Under the current geometry every path I know REACHES the resuming verify only AFTER the recovery-boot checkout gate has put HEAD at the target (Service.Run's gate, runCrashRecovery's gate at install_upgrade.go:228ff, root.go:162's carve-out) — and HEAD=target implies the object is LOCAL, so CauseCommitNotFetched at THIS site may be structurally dead, not merely rare (a checkout of a missing ref fails the boot BEFORE the verify, a different branch entirely). The trace answers: does ANY current path reach the verify with the target object absent? If NO: the leg's map row is REASSESSED like the ddl cell — either retire-with-reasoning (defensive-dead code kept as belt-and-braces, tested at unit level with a stubbed cause) or relocate the oracle to where the fetch machinery GENUINELY fires (the register-by-commit path, rc.04's fix). If YES: the construction rides the Q1 hook, and the object-absence manipulation is sanctioned in the ABORT-arc genre (environment manipulation of real machinery state) ONLY with the producing path named in the arc header — no object surgery for a state we cannot name a producer for (the dead-producer doctrine's exact line). Do not build on the King's 'defensive edge' phrasing alone; verify the edge exists.

Q3 — ARMS: TWO ARCS (one per leg), each running BOTH arms SEQUENTIALLY — resolve-arm first (ends completed), then a fresh crashed-upgrade base for the exhaust arm. Not 4 arcs: the install+lineage setup amortizes and the arms are independent dispatches. Exhaust budgets: reuse an env override if the specs already have one; if not, ADD one in the STATBUS_MIGRATE_UP_TIMEOUT house pattern (env-tunable budgets are established style — seconds in test, real values in production) rather than eating 15 wall-clock minutes per exhaust; either is acceptable, silent hardcoded waiting is the worst option.

Q4 — UNIT: CONFIRMED — one unit: the hook (tiny product change, no-op in production) + the db-unreachable arc + lineage wiring; the commit-not-fetched arc joins the unit only if Q2's trace proves reachability, else its reassessment note lands on the map row instead. Engineer builds immediately on Q1/Q3/Q4; Q2's trace gates only its own leg.
---

author: architect
created: 2026-07-15 02:43
---
Q2 DISPOSITION RULED (architect, 2026-07-15; the trace's three code-cited invariants accepted): (a)-PLUS — retire the map row with reasoning AND DELETE the dead dispatch arm, rerouting any future recurrence to the existing LOUD named human stop. Not (b): the register-by-commit path needs no relocated oracle — its fetch is a single bounded attempt with a loud failure (rc.04 fix, 183-hardened), already live-proven; a 15-minute stall-detecting backoff has no honest home there.

WHY DELETE BEATS KEEP-DORMANT: the house rule is the King's own — dead paths are deleted, never kept as plausible-looking cover. And the replacement guard is STRONGER doctrine than the arm itself: with the CauseCommitNotFetched dispatch arm removed, the classifier (unchanged, service.go:2545) still NAMES the cause, and the classify-then-act's default arm human-stops with that name in the message — loud, actionable, zero retry of a structurally-impossible state. If a future refactor breaks any of the three invariants (caller gate :1134, phase invariant :261+:1893, checkout gate :1903), the box STOPS AND SAYS WHY instead of silently spinning a 15-minute backoff nobody has ever run in anger.

SCOPE OF THE DELETION (engineer verifies callers first): the CauseCommitNotFetched case in the resuming classify-then-act's switch + commitNotFetchedSpec + fetchWithStallDetection IFF they have no other callers — orphaned machinery goes with its only user; anything with a live second caller stays. The CLASSIFIER stays whole (the cause name is what makes the human stop actionable).

HONEST FLAG (the 164-reversal genre): this reverses one sub-shape of the King-ratified STATBUS-109 design (the commit-not-fetched retry arm) on NEW structural evidence — three invariants proving the arm unreachable, none of which were on the table at 109's ratification. It applies two of his own standing rules (remove-wrong-paths; loud guards over standing self-heal). Foreman FYIs him; the build need not wait — the deletion is separable and revertible if he reads it differently.

MAP ROW: reassessed — 'commit-not-fetched backoff leg' → retired-with-reasoning, citing the three invariants + the replacement guard; the UNIT TEST that survives: stub the pruned-object state → assert the classifier returns CauseCommitNotFetched AND the dispatch human-stops with the cause named (proves the classifier + the loud guard, the two things that remain real). The db-unreachable leg proceeds as ruled — its cause is live — and with the Q1 hook + Q3 override already frozen green, that arc is the row's oracle.
---

author: architect
created: 2026-07-15 02:48
---
DB-ARC RESOLVES-ARM BASE RULED (architect, 2026-07-15): (a) — the NEW at-target kill site. Reading (b) is rejected on the map row's own purpose: the row exists to prove THE BRANCH PAIR the standard arcs never exercise, and the resolve-dispatch's FORWARD branch (cleared backoff → re-read → AlreadyAtNew → resumeNewSb → completed) would otherwise never run anywhere — (b) proves the loop but tells the wrong story (an NSO reads 'db blipped → box rolled back' when the rollback was the KILL's Behind-ness, not the blip). The 109 headline is transient → quiet in-process retry → FORWARD completion; the oracle must show it.

THE SITE: `killed-by-system-after-migrations-before-completion` (KindKill), in applyNewSbUpgrading immediately AFTER the migrate step returns success and BEFORE the health check. Placement rationale: earliest instant of the genuine at-target window (ledger at on-disk max + binary at target ⇒ ObservedAlreadyAtNew), which also maximizes the forward work the resume must redo (health → maintenance-off → archive → completion) — the richest forward proof. AC#5 justification at the site: the window between the last migration and state=completed is Go-internal and unreachable by external timing. Same sanctioned genre as the just-approved stall hook.

DUAL USE, deliberate: this site is ALSO the producer my flagless-selfheal real-path successor needs (interim-net ruling, the r19 narrowing) — a real dispatched upgrade killed at-target is exactly the state whose flag the successor then truncates to drive completeInProgressUpgrade. One new site, two queued map needs; note it in the site comment so nobody 'cleans it up' after the first consumer.

ARM FLOWS AS NOW SHAPED: RESOLVES — dispatch B → kill at the new site → next dispatch's resuming classify-then-act → Q1 stall holds → arc pauses db → release → CauseDBUnreachable → backoff → arc unpauses → clears → re-read AlreadyAtNew → forward → row COMPLETED (attempts arithmetic: one kill, one counted resume, different steps — no same-step-twice). EXHAUST — container-restart base as planned, never clears → budget exhausts → data-safe rollback (110). Both arms one arc per the standing Q3 ruling. Engineer builds both in one pass.
---

author: foreman
created: 2026-07-15 04:46
---
DB-BACKOFF RUN 2 RED — REAL PRODUCT FINDING, WITH ARCHITECT (run 29388951223, log tmp/db-backoff-run2-failure.log): the arc's first product catch. Arm 1 reached the stall (t+2s), paused the db, released the stall — then NOTHING until systemd 'Watchdog timeout (limit 2min)' killed the unit. Mechanism: docker pause = HANG-shaped unreachable (connections stall, no error); the resuming verify's observed-state read (service.go:2611) has NO bounded timeout and the pass doesn't heartbeat outside backoffRetry — so the hang variant of db-unreachable (network partition, silent packet drop, frozen container — real NSO production modes) NEVER reaches classification: CauseDBUnreachable fires only on fast-fail reads. The whole 109 classify-then-act is bypassed and the box lands on watchdog exit-restart churn — the exact noise 109 exists to eliminate. The backoff PROBE spec already bounds its tries (5s ctx); the VERIFY read is the gap. Rulings requested: (1) bounded-timeout fix shape + scope (just the verify SELECT or every pre-backoff recovery read; heartbeat during the read?); (2) arc inducement stays PAUSE post-fix (the stronger hang-class test) vs switching to stop's easy fast-refusal class — foreman lean: fix product, keep pause. Run-1 red (images-ready precondition, harness) fixed in ae081d02b with the STATBUS-187 #3 hard-fail catching it in the wild.
---

author: architect
created: 2026-07-15 04:47
---
BACKOFF-ARC RUN-2 RULED (architect, 2026-07-15) — REAL PRODUCT FINDING accepted: hang-shaped unreachable bypasses the whole 109 classify-then-act because the observed-state verify reads are UNBOUNDED; the pass blocks silently until WatchdogSec kills the unit — the exact exit-restart churn 109 exists to eliminate, on exactly the failure modes an NSO's network actually produces (partition, silent drop, frozen container, NAT timeout). The probe spec already models the right pattern (5s per-try ctx); the verify never got it.

1. PRODUCT FIX SHAPE — BOUNDED READS ON THE WHOLE CLASSIFY PATH, one constant, no new heartbeat:
- SCOPE: every DB read between recoverFromFlag entry and backoff engagement — NOT just the resuming verify's SELECT. That includes loadLogRelPath at the function top (a hang THERE blocks before any phase branch; it is best-effort by design and must degrade to its existing nil-fallback on timeout) and every read inside verifyUpgradeObservedStateEx. One shared constant — reuse the probe's 5s per-try bound, never scattered literals.
- CLASSIFICATION: a bounded-read timeout inside the VERIFY classifies as ObservedPositionUnreadable + CauseDBUnreachable — entering the backoff exactly as a fast refusal does. A timeout in a best-effort read degrades to that read's existing fallback. The hang class and the refusal class become ONE class at the classifier, which is the honest model (the operator's network does not care which way the socket died).
- NO NEW HEARTBEAT: with 5s-bounded reads the pass reaches backoffRetry (which self-heartbeats) within seconds; a ticker around the verify would be redundant machinery. WatchdogSec remains the outer net, as designed.
- ENGINEER VERIFIES, not assumes: EnsureDBUp/connect's existing bounds on this path — the run just proved one 'obviously bounded' read wasn't.
- Foreman files the fix ticket (109-completion: 'hang-shaped unreachable must classify', MED, safety-core — engineer builds, my frozen-diff review per the King's rule); the arc re-run is its oracle.
2. ARC INDUCEMENT — KEEP PAUSE, concur, and it is now the STRONGER oracle by construction: pause proves the hang class end-to-end (hang → classified → backoff → unpause → resolve → forward completion), which is the class the run just exposed as broken. Switching to docker stop would prove only the easy fast-refusal class and leave the exposed gap untested — the no-accommodation doctrine forbids it. The fast-refusal class needs no VM arm: a unit test stubbing a refused connection → CauseDBUnreachable covers its classification at zero VM cost.

BOOKKEEPING credit: run 1's red validated STATBUS-187 #3's hard-fail in the wild (the guard caught a harness precondition violation loudly — the fail-fast wave paying for itself), and run 2 is the backoff arc's first product catch — the campaign doing what the King built it for: 'we only find the real errors when we run the real operations.'
---

author: foreman
created: 2026-07-15 06:01
---
DB-BACKOFF RUN 3 (29391895536, log tmp/db-backoff-run3-failure.log): TWO WINS + ONE ARC BUG. Win 1 — STATBUS-190 PROVEN LIVE: the paused-DB hang classified as CauseDBUnreachable in 11s, backoff engaged (6 attempts across the 60s budget), exhausted on schedule — run 2's watchdog wedge is dead. Win 2 — the exhaust-arm PRODUCT story ran end-to-end unaided: at exhaust the rollback stopped all services INCLUDING the paused db (compose stop handles paused, journal 05:52:55), the STATBUS-187 verify-stopped guard passed honestly, volume restored, containers recreated, db healthy in 6s. The red was the ARC's own step: arm 1's db_unpause fired 4s after exhaust, by which time the rollback had already stopped+recreated the container — the step's premise ('the restore needs a live DB') is FALSE, run-disproven. Foreman-ruled arc fix (empirical, no doctrine): arm 1 drops the unpause entirely (never touch the container after the exhaust marker — racing the rollback was the red), arm 2 keeps its load-bearing strict unpause, and the unpause helper stops discarding docker's stderr. Engineer executing; run 4 next.
---

author: foreman
created: 2026-07-15 06:23
---
TRANSIENT-DB-BACKOFF ROW PROVEN — RUN 4 GREEN (run 29393095941, commit f17528214, 2026-07-15): both arms end-to-end on one run. EXHAUST: at-Behind crash base → stall → paused-DB hang classified as CauseDBUnreachable (the STATBUS-190 bounded reads) → in-process backoff engaged → budget exhausted → the rollback stopped the paused container itself, restored, rolled_back with the cause named, NRestarts bounded, data intact. RESOLVES: the NEW at-target crash base (killed-by-system-after-migrations-before-completion) → stall → pause → backoff engaged → unpause within budget → cleared → re-read AlreadyAtNew → FORWARD COMPLETION (state=completed), flag gone, no orphan backup, healthy, data intact. Four runs, three real findings en route: the images-ready harness precondition (caught in the wild by STATBUS-187's #3 hard-fail), the hang-shaped-unreachable product gap (STATBUS-190, fixed + live-proven), and the false arm-1 unpause premise (run-disproven, removed). WITH THIS, THE COVERAGE MAP'S RELEASE-GATING REMAINDER IS EMPTY — every release-gating row is [PROVEN] or honestly [RETIRED] with invariants cited. Remaining on the TICKET (non-release-gating per the architect's rulings, but the King's all-tickets stable gate governs): the two interim-net real-path successors — flagless-selfheal (its producer NOW EXISTS: the dual-use at-target kill site) and the churn successor — plus AC#4's zero-callers end state. Mechanic flips the map row; engineer proceeds to the flagless-selfheal successor.
---
<!-- COMMENTS:END -->
