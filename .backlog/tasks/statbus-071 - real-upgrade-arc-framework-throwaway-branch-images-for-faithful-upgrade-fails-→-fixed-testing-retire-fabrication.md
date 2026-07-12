---
id: STATBUS-071
title: >-
  real-upgrade-arc-framework: throwaway-branch images for faithful "upgrade
  fails → fixed" testing (retire fabrication)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-17 09:05'
updated_date: '2026-07-08 13:46'
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
- The rollback's git restore is CORRUPT (catastrophic abort) -> `4-rollback-abort-write-lands` scenario -> ABORT terminal write lands in ONE pass (state='failed' + error, flag removed — STATBUS-136), then the flagless self-heal converges — **[PROVEN]** local run 2026-07-07 on 089860e65 (dual oracle: also live-proves the STATBUS-039 flagless self-heal)
- The operator RE-ATTEMPTS a broken restore (`./sb install` on a restore-broke box, state='failed' + retained backup_path) -> restore-broke-reattempt arc (to build) -> DUAL-CLASS oracle, both classes REQUIRED: (i) pair-terminal row class — the re-attempt runs (watchdog armed, git-state guard first, db stop, shared restore) -> restore completes -> the row reaches its honest `rolled_back` terminal; (ii) abort row class with STILL-CORRUPT git — the re-attempt REFUSES actionably (ErrRollbackGitCorrupt) BEFORE any destructive step, naming the corruption and the operator's next step: never a mixed-era box, no silent wedge, no crash loop — **[UNPROVEN]** (obligation moved here from STATBUS-111 at its close, architect-ruled 2026-07-12 — this map is the release gate's checklist, so the row cannot silently vanish; design pins in STATBUS-111 comment 1 / final summary; flips [PROVEN] on the green run exactly like the park row). THIS ARC ALSO CARRIES the abort-terminal WRITE-LANDS oracle (architect ruling, 2026-07-12): its abort-row construction — real dispatch of a broken-migration B, post-swap kill, then corrupting the restore inputs on the VM (environment manipulation of real machinery state, not fabricated rows) — produces exactly the state `4-rollback-abort-write-lands` fabricates today; fold that scenario's assert (ABORT terminal lands in ONE pass: state='failed' + error together, flag removed) into this arc's spec. The scenario stays as the interim net and is DELETED when this arc goes green (the r19 pattern); that deletion also drops fabricate_resume_state to its one sanctioned rune-wedge caller.
- The operator UN-PARKS after fixing the cause IN PLACE (the park banner's own advertised remedy: "fix the cause, then re-trigger") -> un-park-to-completion arc (to build; normal priority) -> a RESOURCE-class park where the fix is genuinely external — fill the disk so the upgrade parks before the pull, free the disk, `./sb install` un-parks -> the SAME row runs its fresh attempt to `completed` — **[UNPROVEN]** (architect ruling, 2026-07-12: NOT a health-park-arc leg — that arc's break is release-internal, so "removing the break" there would be a manual DB write = fabrication by another name; the health-park arc honestly tells the release-caused story, where the remedy IS a fix release. Risk is small: waves 9/10 proved the un-park attempt runs the full resume, and completion-after-resume is proven on every green upgrade — only the composition suffix is unproven.)

**A step just stalls (slow, not killed) -> the heartbeat must keep the box alive -> finish**
- DB reconnect stalls after a restart -> `postswap-watchdog-reconnect-arc` — **[PROVEN]**
- Archive-backup stalls -> `postswap-archivebackup-watchdog-arc` — **[PROVEN]**

**The new version can't serve its users (health) -> park alive-idle, wait for the fix**
- Health gate refuses a can't-serve version -> `postswap-health-park-arc` (doc-029) -> parks at-target with the named health reason, sirens exactly once per park event, parked-skip boots stay alive-idle, deliberate un-park grants one fresh attempt, re-park with fresh reason + second siren, daemon ACTIVE after re-park, and a genuine fix release DISPLACES the standing park (B superseded with its story intact) and completes with data intact — **[PROVEN]** run 29171998401 (2026-07-12, wave 10 — the arc's first full end-to-end green; waves 1-9 each caught a real product bug en route: STATBUS-148 health gate, STATBUS-154 teardown race + invisible writer, STATBUS-147 daemon-down, STATBUS-159 parked-blocks-claim). This IS the real-path park proof under the STATBUS-145 geometry (doc-028's reclassification): the r19 fabricated park scenario was the interim net and is now due for deletion, with fabricate_resume_state dropping to its ONE sanctioned dead-producer caller (rune-wedge) per the King's carve-out ruling.
- A fix release FAILS and rolls back onto the DISPLACED version's binary (B parked -> C claims, displacing B to superseded -> C fails post-swap -> rollback puts the box on B) -> C-rollback resurrection leg (to build; rides the STATBUS-160 package) -> the box boots + the operator runs `./sb install`: B STAYS superseded (no resurrection through any door — the deleted reconciler, the narrowed install upsert, the terminal-resurrection DB trigger), C stays rolled_back, the state log shows NO terminal-to-completed transition, and the refuse names the re-dispatch remedy — **[UNPROVEN]** (architect ruling on STATBUS-160, 2026-07-12: 'completed' means THIS VERSION VERIFIABLY SERVES — only serve-proven writers may write it; the running-but-unrecorded version is an observed fact via system_info, never a ledger edit)

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
STATUS (2026-07-07, supersedes the 2026-06-21 line): FOUNDATION DONE AND PROVEN — working + failing arcs GREEN on real VMs (originally runs 27807092720 / 27811604893; re-proven post-110/109 on run 28679526112). STATBUS-118 constructor shipped (0b1b07ef4); X/Y RESOLVED (King): build-on-CI + pull (doc-020 revised). ~11 coverage cells [PROVEN]. The U-campaign is executing the remainder (engineer's plan, architect-approved 2026-07-07): U1 = first live contact for the five kill arcs (run 28832014634) — all five red, ZERO product findings, two harness bug families diagnosed + fix list dispatched (comment #6, the ledger); U2 = rollback-restore-watchdog arc re-scoped observational→asserting (architect: SHIP + one anti-vacuity one-liner; VM run pending); U3 = STATBUS-136 abort-terminal fix built + architect-shipped (unblocks U4); U4 = split into TWO disjoint oracles per the architect's ruling — (a) rollback-pair-terminal via the PRE-SWAP route (2 kills; the V_fail route needs 4 and traverses forward machinery) + (b) rollback-abort-write-lands (the r17 shape, one boot, zero kills; Behind via a VALID-named far-future migration, never the invalid-version file = the 138 bug); U7 = the 044 rune-wedge scenario built (3-postswap-rune-wedge, uncommitted at note time).

OPEN KING DECISION — the AC#4 ⇄ park-class fabrication carve-out (the true boundary of "retire fabrication"): the r19-green park scenario and the rune-wedge scenario CONSTRUCT resume states that real dispatch cannot present on cue (r12 proof, STATBUS-044 comment #6). Architect's framing before the King: sharpen the rule — "no fabrication where the real path can reach; construction permitted ONLY for a class with a written unreachability proof, consumed by the real recovery reader in the run"; today exactly ONE class qualifies (resume-state/boot-migrate). AC#4's "zero callers" is GATED on this ruling.

DISPATCH (remaining, in campaign order):
- Harness fix list from U1 (comment #6): shared kill-confirmed helper (fresh PID at kill time; never release a stall after an unconfirmed kill), transport-aware probes, split install-helper contract (RED midpoint then GREEN terminal).
- Re-run the five kill arcs fixed — the after-commit pair's re-run IS the STATBUS-105 measurement (expected terminal: rolled_back per the King's ratified rule).
- U2 VM run (cover-holds proof); U4 (a)+(b) builds (mechanic, ruled constructions); 5d deletes of superseded legacy scenarios after their arc replacements are PROVEN; 5e = fabricate_scheduled_upgrade_row deletion at zero callers (gated on the carve-out ruling; 2 arc callers remain: preswap checkout/backup).
- Plus STATBUS-095/096 (timeout + OOM failure modes; fill the two [TODO] cells).
- Hardening riders folded in from the board sweep: 094's two items + 101's EXPECT_RED option (comments #4/#5).

FOLDED IN (2026-06-21, King-directed): STATBUS-091 (phase-2 charter — Waves 1+2 complete: 086 CLI verbs, 072 amend-conveyance, 087/088/089/090 fixes all landed) + STATBUS-075 (cut-rc04 campaign — install RC v2026.06.0-rc.04 cut). Both CLOSED; their only live remainder was this framework. 2026-07-06 board sweep folded in: 013 (spec home = 105, arcs here), 094, 101.

Designs: doc-012 (build-spec), doc-016 (kill-arc reshape plan), doc-017 (after-commit arcs). Full run-by-run build history (every commit + VM run, the bug-by-bug hardening) preserved in this task's git history.
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
<!-- COMMENTS:END -->
