---
id: STATBUS-044
title: >-
  battery-readiness: verdict-split the resume-died scenario + build the
  rune-wedge scenario + systemd empirics
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:51'
updated_date: '2026-07-07 02:55'
labels:
  - install-recovery
  - testing
  - battery
  - upgrade
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-resume-died-rollback.sh
  - doc/diagrams/upgrade-timeline.plantuml
  - STATBUS-039
  - STATBUS-042
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: (already leads the ticket) the park proof — delivered. Remaining: the rune-wedge takeover proof + systemd counter empirics.
> BENEFIT: the exact failure Norway already lived through once (the rune wedge shape) gets a standing scenario proving takeover → forward → completed with zero restores — before Norway relies on it again; and the NRestarts/reset-failed semantics the crash-loop gate reads are confirmed rather than assumed.
> STAGE: Stage 1 proof work.
> COMPLEXITY: mixed — architect owns the rune-wedge scenario (AC#1, assigned); operator/tester run the one-VM systemd empirics (AC#2).
> DEPENDS ON: nothing.

---

NORTH STAR (read this first): when an upgrade keeps killing the server, the system must STOP RETRYING, STAY ALIVE, and CALL FOR HELP ONCE — never loop forever unnoticed (the rune failure). The mechanism is built and shipped (STATBUS-046). THIS ticket is the PROOF: one test on a real cloud VM that crashes an upgrade during its real migration window three times, watches it park + siren, then un-parks it deliberately and watches it complete. Everything below and in the comments is detail in service of that one run.

CURRENT STATE + THE APPROVED PLAN (King approved comment #6, 2026-07-04): 12 VM attempts exposed a product hole — migrations actually run at service BOOT (boot-migrate), before the crash counter starts, so a crash there loops uncounted. Approved fix: count attempts BEFORE boot-migrate (both entrypoints), stamp the boot-migrate step on the flag so same-step-twice covers it, parked servers skip boot-migrate, exhaustion at the early guard parks (never auto-rollback). Then the scenario kills during boot-migrate — simpler than the old construction AND tests the real window. Order: engineer builds the counting fix → mechanic rebuilds the scenario per comment #6's substitutions → VM run is the oracle. That run also closes STATBUS-131 AC#3 (siren from a .env.config-configured callback) and the doc-021 open gap.

--- Original battery items (pre-park-arc; still valid, deferred behind the run above) ---

Three items that gate the deferred install-recovery VM battery (post-rune-install window; commits to scenarios must respect the freeze windows — land BEFORE a battery run starts or between runs, never during).

1. SCENARIO EXPECTATION UPDATE (battery-blocking, found in STATBUS-042): test/install-recovery/scenarios/3-postswap-resume-died-rollback asserts the PRE-039 contract — death during Phase=Resuming ⇒ always rolled_back (UPGRADE_DIED_DURING_RESUME). Post-039 (5eacd6305) the Resuming branch is ground-truth-gated: an AT-TARGET fabrication resumes FORWARD and converges to completed; only a POSITIVELY-BEHIND fabrication rolls back to the upgrade's own snapshot. The scenario almost certainly fabricates at-target state (a Resuming flag on a converged box) → RED against rc.02 for the RIGHT reason. Split it: fabricate-Behind → assert rolled_back + identity restore; fabricate-AtTarget → assert forward convergence to completed. Marked in doc/diagrams/upgrade-timeline.plantuml's TEST note.

2. RUNE-WEDGE SCENARIO (STATBUS-039 verification plan item 2): fabricate the rune shape on a VM — in_progress post_swap row + stale proxy container + crash-looping unit (NRestarts past the gate) — and assert: ./sb install takes over (SIGKILL-class, no SIGTERM delivered), resumes forward, recreates the full service set incl. proxy at the flag target, converges the row to completed, no restore ran, flag removed, a subsequent install is nothing-scheduled. Owner: architect (reconstructed the shape in the Go tests).

3. SYSTEMD EMPIRICS (engineer's confirm-empirically items from the 039 review): (a) NRestarts semantics across the exit-42 handoff — confirm the planned restart bumps the counter by exactly 1 and the per-dispatch reset-failed zeroes it (STATBUS-039 F2); (b) `systemctl --user reset-failed` on an ACTIVE unit resets the restart counter on the fleet's systemd version (≥244 behavior) — on older systemd the gate degrades to pre-039-conservative (logged), confirm the degradation is what ships. Both are one-VM checks; fold into the battery prep.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 rune-wedge scenario lands in test/install-recovery/scenarios/ and proves takeover→forward→completed with zero restores on a fabricated rune shape
- [ ] #2 NRestarts-across-exit-42 + reset-failed-on-active-unit confirmed on a VM (or the documented conservative degradation confirmed for older systemd)
- [ ] #3 All scenario commits land outside battery runs (freeze-window discipline)
- [x] #4 3-postswap-resume-died-rollback rewritten to the four-case verdict matrix (canary-self-heal / transient-forward-succeeds / persistent-forward-loops / behind-rolls-back) ONLY AFTER the King settles the loudness question for the persistent case — on hold until then
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CORRECTION + HOLD (foreman code-trace, 2026-06-12, architect concurs — supersedes the description's item 1 and the original AC#1): the architect's "at-target fabrication converges to completed" model was WRONG for this scenario's shape. Actual post-039 behavior at Phase=Resuming, verdict AtTarget/Unknown: recoverFromFlag → resumePostSwap (forward again) — it does NOT mark completed. resumePostSwap's container canary marks completed ONLY when every version-tracked container is already at the flag target; otherwise applyPostSwap re-runs, and the scenario's kill is PINNED in the unit env through the whole watch window → the kill fires again → die → restart → LOOP: row stays in_progress, NRestarts climbs, the scenario's Phase 6 times out (its own "OLD retry-loop wedge" message). That is the 039 tradeoff BY DESIGN — at-target never rolls back (data loss past maintenance-off); it retries forward, loud (the posture that kept rune at zero data loss for 18 days).

CORRECT VERDICT-AWARE MATRIX (four cases, matched to real behavior):
0. at-target + containers ALREADY at flag target → immediate canary self-heal → completed, applyPostSwap never runs (the rune shape — covered by the rune-wedge scenario, item 2).
1. at-target + TRANSIENT failure (one-shot inject) → forward retry succeeds → completed.
2. at-target + PERSISTENT failure (pinned inject — the current scenario's shape) → loops forward, stays in_progress + loud, NO rollback. WHAT TO ASSERT HERE DEPENDS ON THE KING'S OPEN LOUDNESS DECISION (degraded-state/alert after N clearly-non-transient forward failures vs loop-loud-forever). Architect's input for that decision: any escalation must be OBSERVABILITY-only (named degraded signal / callback after N retries) — never a direction change; rollback stays forbidden at-target regardless of N.
3. behind → one-shot rollback to the upgrade's OWN snapshot (identity-keyed).

STATUS: scenario rewrite ON HOLD until the King settles loudness (foreman carrying the fork to him). Item 2 (rune-wedge scenario) PROCEEDS — it is case 0, independent of the loudness question. Item 3 (systemd empirics) unaffected.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-03 21:12
---
PARK-SCENARIO ASSERTION SPEC (architect, 2026-07-03, pre-staged for the overnight rewrite — the run is the oracle; these are the observables that make the run's verdict UNAMBIGUOUS. Grounded in slice-1 as shipped: resumeEscalation + parkUpgrade + the parked-skip + the three deliberate triggers).

SCENARIO SHAPE (3-postswap-resume-died, rewritten): drive the post-swap resume to repeated process death (the existing pinned-kill mechanism), then assert PARK not loop, then prove UN-PARK.

ASSERT AFTER THE KILLS (park state):
1. ROW: state='in_progress' AND recovery_parked_at IS NOT NULL AND recovery_attempts reflects the path taken — same-step-twice kills at ONE step park at attempts 2-3 with reason matching 'two consecutive crash-deaths at step "<step>"'; varied-step kills park at attempts 4 with reason matching 'crash-resume budget exhausted: 3 process deaths'. Pin WHICH path the scenario drives (pinned-kill at one step ⇒ expect the same-step-twice message — the budget message showing up instead means the dying-step write-ahead broke).
2. UNIT ALIVE-IDLE: systemctl is-active == active; NRestarts BOUNDED (≤ deaths + a small constant) and FROZEN across a settle window (sleep N; NRestarts unchanged) — the anti-rune assertion, the single most load-bearing check.
3. SIREN ONCE: exactly ONE STATBUS_EVENT=parked callback in the log across the whole scenario INCLUDING two extra service restarts after park (each restart must log the skip line 'is PARKED … skipping automatic resume' and must NOT increment recovery_attempts — read the column before/after).
4. FLAG: still on disk (parked row keeps it); phase unchanged by skips.
5. NEVER: state='rolled_back' at any point; no rollback log markers (at-target exhaust must park, never roll back — 039).

ASSERT UN-PARK (the operator contract, both arms if cheap, install arm at minimum):
6. ./sb install → log 'un-parked upgrade id=N (deliberate ./sb install)' → row parked_at IS NULL → exactly ONE fresh attempt runs (recovery_attempts == 1 after resume starts). If the target is still broken: it re-parks (attempts small, fresh reason, ONE new siren — the fires-once contract is per park EVENT). If the kill-injection is lifted first: the fresh attempt COMPLETES — the happy un-park ending, preferable as the scenario terminal since it also proves the pipeline is undamaged by the park/un-park cycle.
7. (cheap extra) NOTIFY apply arm: upgrade_apply NOTIFY on the parked row → row leaves parked (rescheduled, counters reset) — proves edit 6.

ANTI-ASSERTIONS (do NOT assert): journald line ordering beyond the named markers; exact timestamps; NRestarts == an exact number (bound it, don't pin it — systemd's counter includes unrelated starts).
---

author: architect
created: 2026-07-03 21:12
---
AC#4 HOLD LIFTED (architect, 2026-07-03): the 'King settles the loudness question' condition is now MET — decision D3 (recorded on STATBUS-046 comment 3) IS the loudness settlement: the persistent-forward case no longer loops-loud-forever, it PARKS under the death budget / same-step-twice with a named reason, siren once, alive-idle. The four-case verdict matrix in the implementation notes updates as: case 0 (canary self-heal) and case 1 (transient forward succeeds) unchanged; case 2 (persistent) now asserts the PARK-SCENARIO ASSERTION SPEC in comment #1 (park not loop, un-park contract); case 3 (Behind rolls back) unchanged. The rewrite is buildable overnight against slice 1 as shipped; note the old scenario name '3-postswap-resume-died-rollback' should be renamed — its terminal is now parked-then-unparked, not rollback.
---

author: foreman
created: 2026-07-03 21:44
---
PARK SCENARIO BUILT + COMMITTED + PUSHED: 8641445eb (3-postswap-resume-died-parked.sh, 509 lines, + README row + timeline TEST-note rewrite; SVG regen in-commit). Mechanic built spec-first against comment #1; architect APPROVED with the kill arithmetic VERIFIED against shipped code (handoff-resume = attempt 1 with zero deaths → kill #1 at migrate-up → resume 2 rolls the prior step → kill #2 → resume 3 = same-step-twice → PARK at attempts==3, exactly 2 kills, same-step reason). Mechanism: external SIGKILL gated on the flag's Step field (the death budget counts DAEMON deaths; inject classes either don't kill the daemon or sit past the self-heal convergence point — the STATBUS-099 product-impossible finding still holds for THAT site and is preserved in the rewritten timeline note). All five assertion groups + extra-restart re-assertions + the install-arm un-park happy terminal implemented. RESIDUAL (labeled): the NOTIFY-arm un-park is not exercised — it shares the reset consts with the CLI arm; a dedicated variant only if a regression appears. SIDE FINDINGS: STATBUS-130 (stale one-shot-latch docs, two files) + STATBUS-131 (REAL product gap, HIGH, architect-verified three-legged: UPGRADE_CALLBACK is not propagated by config generation and .env is rewritten at install AND upgrade step 3.1 — the park siren is structurally DISARMED on real boxes; production Slack survives only because it rides the separately-enumerated SLACK_TOKEN). NEXT: the VM RUN is the oracle — images for 8641445eb building now; the scenario run launches when they publish. AC#4 checks only on a GREEN VM run.
---

author: foreman
created: 2026-07-04 00:22
---
PARK-ORACLE VM CAMPAIGN: 12 runs overnight (2026-07-04, ~00:00-02:30), PAUSED at a genuine scenario-design collision — AC#4 defers to a morning design ruling. THE LEDGER (every failure named, zero hand-waving): r1 runner killed by a tool timeout · r2+r6 orphan-VM name collisions (each collision run self-cleaned the orphan) · r3+r4 local board-commits embedded in the uploaded binary (two race windows: at launch and at the mid-run rebuild) — total-commit-freeze discipline adopted · r5 the tester environment killing long tasks → detached-nohup execution shape · r7 isolated the TRUE harness bug: the release-pinned depth-1 clone can never resolve HEAD → the missing fetch+checkout stage from 0-happy-upgrade:118 (commit 0fafe16f2) · r8-r10 the OLD v2026.05.2 daemon silently declines to claim fabricated rows (r10 kept-VM autopsy, SIGQUIT goroutine dump: idle in its main select loop; predicate opaque + superseded) → restart-onto-HEAD + fabricate declares docker_images_status AND release_builds_status ready (070c0aed8, d02798055; r8 also gave the new claim gate its FIRST LIVE FIRING — correctly refusing an unverified row) · r11 macOS bash-3.2 quote-parity trap in the fabricate heredoc (9d5303c82, guard-commented) · r12 THE DESIGN COLLISION: the restarted HEAD daemon runs BOOT-MIGRATE at startup — applied all 9 pending migrations in 6s and marked the version completed, consuming the upgrade before dispatch; no migrate-up window can exist on this path. MORNING DESIGN QUESTION (with the architect): open the kill window via post-boot-settle fabrication + the migrate.go inject-stall site (stall-file choreography vs boot-migrate needs mapping), or a constructed-B synthetic slow migration (but boot-migrate applies it BEFORE resumePostSwap — exposing an interesting uncovered gap: a boot-migrate crash loop is not counted by the 046 death budget, worth a doc-021 step-list note), or a cleaner third shape. All logs: tmp/vm-run-park-scenario-*.log. Scenario code itself: committed (8641445eb + the four campaign fixes), assertions still unexercised.
---

author: architect
created: 2026-07-04 00:23
---
MORNING DESIGN ANALYSIS (architect, overnight — for the King's review alongside the summary; no code tonight). r12's revelation is BIGGER than a scenario-construction problem: it exposes that the 046 budget's INCREMENT PLACEMENT does not cover the window where resume-time migrations actually run.

THE REFRAME: on any post-crash restart, BOOT-MIGRATE (service Run + install ladder, the rc.65 schema-skew guard) applies the target's pending migrations BEFORE recoverFromFlag/resumePostSwap — the tree is already checked out at the target after the pre-swap git checkout, so by the time applyPostSwap step 3.5 runs it is a no-op. Step 3.5 deaths — the window the park scenario was specced to drive — are therefore NEAR-IMPOSSIBLE in the real system; the REAL migration-death window on a resume is BOOT-MIGRATE. And boot-migrate deaths are INSIDE the D3-ratified budget boundary (flag-write → flag-removal) but UNCOUNTED by the shipped implementation (incrementRecoveryAttempts fires at resumePostSwap entry, which boot-migrate precedes). A migration that OOM-kills the box on every restart = an uncounted crash loop = the rune class, in exactly the window where heavy migrations actually run. The engineer's (B)-candidate note ('kills land in a boot-migrate loop the death budget never counts') was not a test artifact — it was the system's real shape showing through.

FIX DIRECTION (engineer-buildable after a design note; arguably within D3's ratified boundary since it makes the implementation match the ratified coverage, but King's morning nod requested since it moves budget semantics): HOIST the increment to the start of the flag-owned recovery pass — as soon as a service-held flag with a dead PID is detected (service Run and the install ladder, BEFORE boot-migrate) — and stamp a StepBootMigrate marker around the boot-migrate so same-step-twice covers it. resumePostSwap's increment becomes conditional (don't double-count within one pass). The parked-skip check must also move ahead of boot-migrate on the service path, or a parked row's restart still pays a full boot-migrate before skipping (benign but noisy).

SCENARIO ANSWER (defer until the fix direction is decided): with the hoisted increment, candidate (B) — constructed-B target + synthetic pg_sleep migration — becomes the CLEAN construction: kills land in boot-migrate, are COUNTED, same-step via StepBootMigrate → park; it tests the REAL window rather than the near-unreachable 3.5 one. (A)'s stall-file dance remains the fallback if the 3.5 path specifically needs exercising. Assertion spec (comment #1) holds with one substitution: the expected same-step message names boot-migrate's marker, not migrate-up.

All 12 run logs: tmp/vm-run-park-scenario-*.log; the 046 BUILD is untouched by this — shipped + dual-reviewed; only this AC (scenario green) defers on the morning decision.
---

author: architect
created: 2026-07-04 12:12
---
PARK-SCENARIO RULING + BUDGET-FIX RECOMMENDATION (architect, 2026-07-04 morning — written for direct approval; every claim re-verified against shipped code today).

WHAT r12 PROVED. When a crashed upgrade resumes, the pending migrations are applied by the boot-time schema catch-up (`sb migrate up` — service.go:1854 on the daemon path, install_upgrade.go:237 on the ./sb install path), which runs BEFORE the recovery routing (recoverFromFlag, service.go:1902). The working tree is already at the target by then (the recovery-boot checkout), so the migration delta lands in that boot window and the migrate step inside the resume pipeline is a no-op. Two consequences: (1) the park scenario's kill window — flag step 'migrate-up' — can never open on a resume; the scenario was specced against a window the real system no longer reaches. (2) Far more important: a migration that kills the box on every restart (say, OOM on a large table rewrite) crash-loops in that boot window UNCOUNTED — the death budget's counter increments only later, at resume entry (service.go:5817). That is the rune loop class, in exactly the window where heavy migrations actually run. The ratified budget boundary (every death between flag-write and flag-removal, doc-021/D3) already covers this window on paper; the shipped implementation does not yet.

RECOMMENDED FIX (product; engineer-buildable from this note):
1. Move the attempt counting to the START of the recovery pass: when a boot finds a service-held forward flag (dead holder), increment recovery_attempts and consult the escalation rules BEFORE the boot migrate, on both entrypoints. A terminal verdict here PARKS — never an automatic rollback from this early guard: park touches no data, and a deliberate ./sb install un-parks into the existing careful routing, which can still roll a genuinely-behind box back.
2. Stamp the flag's step field 'boot-migrate' around the boot migrate so two consecutive deaths there park via the existing same-step-twice rule.
3. ONE consult+increment per process lifetime: the resume-entry consult (service.go:5805-5825) is skipped when the boot-time one already ran. Verified subtlety: without this, a boot-migrate that SUCCEEDS right after a boot-migrate death false-parks on a stale same-step comparison.
4. A PARKED row skips the boot migrate too. This is what makes park actually deliver alive-idle for this failure class — otherwise every restart re-runs the killer migration and the crash loop continues despite the park. Named tradeoff: a parked box may then log schema-mismatch errors from the daemon's own queries until the operator acts — loud but alive, the right side of the trade; ./sb install un-parks with a fresh budget and re-runs the migration deliberately.
Arithmetic unchanged: the planned post-swap handoff is still attempt 1 with zero deaths; budget 3 and same-step-twice semantics untouched — only the counting point moves earlier so boot-window deaths self-count. Implementation wrinkles for the engineer (named, none blocking): flock acquisition moves earlier for forward flags (the step-stamp writes need it); on the install path the un-park block (install_upgrade.go:265) and the DB connect (:253) currently sit AFTER its boot-migrate and must move ahead of it; the 42703 fail-open bootstrap pattern (service.go:5792-5804) applies to the hoisted reads verbatim.

SCENARIO (the AC#4 oracle, buildable once the fix lands). Fabricate the RESUME state directly — no dispatch, no claim gate involved: in_progress row + service-held forward flag (dead PID, target = current HEAD, checkout a no-op) + ONE synthetic sole-pending migration on disk (far-future version) whose body is pg_sleep(3600). Restart the unit: pass 1 stalls inside boot-migrate with 'boot-migrate' on the flag → SIGKILL the daemon (kill gate = the flag's step field, the committed mechanism) → pass 2 same → pass 3 parks at attempts==3, exactly 2 kills, reason naming boot-migrate — identical arithmetic to the committed scenario, now at the real window. Assertion spec (comment #1) holds with two substitutions: the same-step message names 'boot-migrate', and the parked-skip log line moves to the boot path. Un-park terminal: delete the synthetic migration, run ./sb install → fresh attempt → clean boot-migrate → completed — the happy ending that also proves the pipeline undamaged by the park/un-park cycle. The alternative construction (stall-knob inside the resume migrate step, post-settle fabrication) is NOT recommended: it exercises a window the real system cannot reach, and its kills would land in the next boot's migrate anyway — uncounted until this fix lands.

DECISION ASKED: approve (a) the budget fix — count and park boot-window deaths, parked rows skip the boot migrate — and (b) the scenario shape above. The fix makes the implementation match the already-ratified budget boundary; the nod is requested because it moves where counting happens and adds one new step name.
---

author: foreman
created: 2026-07-04 19:49
---
KING APPROVED comment #6 (2026-07-04 morning), with the instruction to lead the ticket with its north star — description updated accordingly. Dispatch: engineer builds the counting fix (budget hoist + boot-migrate step stamp + parked-skip + park-only early guard, per comment #6's wrinkle list), architect reviews hands-on, then mechanic rebuilds the scenario with comment #6's substitutions. King also raised a design question — why a budget of 3 instead of classify-transient-vs-permanent-and-stop — answered in session: B/C (errors that speak) already park on FIRST occurrence with zero retries; the budget exists only for silent process deaths that carry no classifiable signal, where re-running IS the classification instrument; same-step-twice parks at 2; the 3 only admits deaths at DIFFERENT steps (progressing-but-unstable). If the King wants the cap tightened after reading that rationale, it is a one-constant change (RecoveryDeathBudget).
---

author: foreman
created: 2026-07-04 20:25
---
BUDGET HOIST SHIPPED: cc660280f (2026-07-04). Comment #6's four parts + both review fixes: F1 parked-skip at the top of recoveryRollback (a parked row can never auto-restore via Behind / Unknown-exhaust / flagless routes) and F2 the pre-existing un-park insta-re-park bug (deliberate install un-park now clears the flag's Step/PriorDeathStep so the operator really gets ONE fresh attempt). Engineer refinement A (guard owns the PriorDeathStep roll; resume preserves) architect-verified as load-bearing. Five new unit tests. Dual-reviewed: architect fix-then-ship → ship; foreman independent build+vet+test green. NEXT: mechanic rebuilding the scenario per comment #6's substitutions (dispatched; flag fabricated at phase=post_swap per architect's reminder; STATBUS-131 AC#3 folded in if cheap — callback via .env.config only). Then the VM run.
---

author: foreman
created: 2026-07-04 21:15
---
LEDGER r13 (first run of the rebuilt scenario, fb5eb6c18 + hoist cc660280f): FAILED at the new callback-injection step, before any kills. Two independent bugs, autopsy-pinned on the kept VM then deleted: (1) PRODUCT FINDING — generated .env.config has no trailing newline, so the scenario's append glued onto 'ADMINISTRATOR_CONTACT=' (line 29); this also bites any real operator following the now-documented append-to-.env.config flow — one-line config-writer fix proposed to the King. (2) HARNESS FOOTGUN — sudo -i inside VM_EXEC escapes special characters EXCEPT dollar signs (documented sudo behavior), so $STATBUS_EVENT expanded to empty in transit; the injected callback could never have matched the siren assertion. Fix pass dispatched to mechanic: callback becomes a script FILE on the VM (matches ops/notify-slack.sh's reference shape, no $ through the layers), glue-proof append guard, VM_EXEC comment documents the sudo -i trap. Neither bug touches the hoist or the kill choreography — the scenario never reached them.
---

author: foreman
created: 2026-07-04 22:54
---
LEDGER r18 (f9bdac46d + approved-134-in-binary, provenance noted): THE PARK ORACLE WENT GREEN through every assertion group. Kill #1 at t+0s (both deterministic gates: step stamp + active pg_sleep); kill #2 at t+31s on the prior_death_step ''→boot-migrate transition; PARK at attempts==3 EXACTLY, reason 'two consecutive crash-deaths at step "boot-migrate" — deterministic hang (same-step-twice)'; unit alive-idle, NRestarts=2 bounded+frozen across the 30s settle (the anti-rune assertion); siren EXACTLY ONCE via the .env.config-configured callback (STATBUS-131 AC#3 leg observed); flag present post-park (135 live); never rolled_back; both extra restarts logged the boot-path parked-skip, attempts unchanged, no re-siren; deliberate ./sb install un-park granted ONE fresh attempt (reset budget) which COMPLETED — VM row terminal: completed | attempts=1 | parked=f (F2 contract end-to-end). ONE RESIDUAL RED, outside the park mechanism: the un-park install's final idempotent refresh pass failed step 10/16 (Database sessions) on a single-probe 'pool still saturated' verdict immediately after cleanOrphanSessions killed the scenario's orphans — autopsy shows 16/30 connections minutes later, a self-resolving reconnection-burst transient on the max_connections=30 test box. Architect ruling whose bug (foreman's read: product — the check needs settle/retry, not single-probe fail with 'fix and re-run' noise). AC#4 checks on the next fully-green run; the substance is proven.
---

author: foreman
created: 2026-07-04 23:21
---
LEDGER r19 (440c14cb2) — GREEN. ALL SCENARIOS PASSED. Full oracle end-to-end on one VM: two same-step deaths at boot-migrate → PARK at attempts==3 → alive-idle (NRestarts bounded+frozen) → siren exactly once via a .env.config-only UPGRADE_CALLBACK (incl. two extra skipped restarts) → never rolled_back → deliberate ./sb install UN-PARK (exit 0, UN-PARKED line logged) → exactly ONE fresh attempt → COMPLETED (row: completed|1|f) → flag absent post-completion, no orphan backups, health 200, demo data intact and snapshot-matched. The STATBUS-139 sessions-verdict fix held at the exact spot r18 red-flagged (install exit 0). AC#4 CHECKED. The park arc is closed run-proven: comment #6 hoist (cc660280f) + F1/F2, 135 flag-survives-park, 134 restored rollback pair bound, 131 carry-through, 139 sessions verdict — every piece observed live. Campaign total: 19 runs, every failure named. REMAINING on this ticket: AC#1 rune-wedge scenario, AC#2 systemd empirics (pre-park battery items, unchanged). Follow-up noted: doc-021's closing line ('end-to-end oracle outstanding') can now cite r19; STATBUS-134's own pair-terminal scenario (with 136) is the next oracle to build.
---

author: foreman
created: 2026-07-07 02:55
---
AC#1 CHECKED — the rune-wedge scenario went GREEN on its second run (2026-07-07, night pair round 2, HEAD b709e82ef): fabricated rune shape (in_progress row + post_swap flag with dead holder, stale-but-SERVING proxy — the first run refuted proxy-removal: it severs the recovery's own DB route, filed as STATBUS-143) → ./sb install took over with the SIGKILL-class quiesce (never SIGTERM, flock-confirmed death), resumed forward, recreated the full service set at the target, converged to completed with attempts==1, ZERO restores (rolled_back_at NULL enforced), demo data byte-identical, flag removed, second install read nothing-scheduled. The one-shot live rune recovery now has its standing regression net. Remaining on this ticket: AC#2 systemd empirics (ride-along on a kept campaign VM).
---
<!-- COMMENTS:END -->
