---
id: doc-016
title: >-
  STATBUS-071 §9(5) implementable plan — kill-scenario reshape +
  fabricate-retirement (AC#3/AC#4)
type: specification
created_date: '2026-06-19 07:43'
---
# STATBUS-071 §9(5) — kill-scenario reshape + fabricate-retirement (implementable)

**Audience:** engineer (build, one-breaker-at-a-time + freeze protocol), foreman (review/commit/VM-prove). **Inputs:** engineer sketch tmp/engineer-071-step5-plan.md + architect reconciliation (mem #837 fabricate-retirement, #838 inject map). **Status:** design-pass complete; 5a is the priority. **Both arcs GREEN** (working re-stamp + failing clean-slate AC#2) — the framework is proven; this is the fruition.

## 0. The ONE mechanism (AC#3) — and the key correction
Every kill scenario fakes ONLY the SCHEDULING: `fabricate_scheduled_upgrade_row` (data-helpers.sh:266) hand-INSERTs a daemon-down `scheduled` public.upgrade row — needed ONLY because the legacy baseline (v2026.05.2, pre-086) had no register/schedule. **The CRASH is ALREADY REAL** — every reshape-target scenario already drives the crash through the product's real inject points via `STATBUS_INJECT_AT` + `./sb install` inline-dispatch.

**RESHAPE = a MECHANICAL swap, family-wide:** `fabricate_scheduled_upgrade_row` → real `./sb upgrade register` + `schedule` (086 RunSchedule with the daemon quiesced → the SAME persistent daemon-down `scheduled` row, for real). Baseline shifts v2026.05.2 → base_sha (install_statbus_at_sha). The `STATBUS_INJECT_AT` crash + the `./sb install` inline-dispatch + the recovery assertions are UNCHANGED.

**CORRECTION (load-bearing) to the sketch §line 11 "no mid-migrate KillHere → that's why mid-migration scenarios fabricate":** WRONG, per mem #837 + the inventory below. The mid-migrate inject points EXIST and the CAT-C scenarios ALREADY USE them (migrate.go:388 during-migration, :911 between-migrations, :202 mid-tx via MidTxPauseSQL, :844/:845 after-commit). So CAT-C is the SAME swap as CAT-A/B — NOT a "needs new inject / self-failing migration" special case. This collapses §9(5) to a near-uniform swap + a few deletions. Q5-2's "prefer self-failing migrations for CAT-C" is therefore moot for the mid-migrate kills (the inject is real); it applies ONLY to the one true no-inject case (worker-ddl-deadlock).

## 1. Inventory (verified from the scenario files: fabricate + inject class)
**CAT-A — KillHere kills, real inject** (swap scheduling, keep inject):
- 2-preswap-backup-kill (killed-by-system-during-preswap-backup, exec.go:618)
- 2-preswap-binary-swap-kill (:4326)
- 2-preswap-checkout-kill (killed-by-system-during-preswap-checkout, service.go:4261)
- 3-postswap-container-restart-kill (:4779)
- 4-rollback-kill (C9 = builtin-rollback :5620)

**CAT-B — STALL/timeout/watchdog, real inject** (swap scheduling, keep stall knobs):
- 3-postswap-archivebackup-watchdog, 3-postswap-archivebackup-resume, 3-postswap-migration-timeout (migrate.go:363), 3-postswap-watchdog-reconnect, 3-postswap-resume-died-rollback, 4-rollback-restore-watchdog

**CAT-C — mid-migrate, real inject ALREADY USED** (SAME swap — corrected):
- 3-postswap-mid-migration-kill (:388), 3-postswap-between-migrations-kill (:911), 3-postswap-mid-tx-kill (:202 MIDTX_CLASS), 3-postswap-migrate-killed-after-commit (:844/:845)

**DELETE (subsumed / legacy):**
- 3-postswap-migration-deterministic-error (inject=none; fabricates) — **SUBSUMED by the failing arc (d)**: the real V_fail → rollback → clean-slate now proves the same deterministic-error-rolls-back-cleanly contract. DELETE, don't reshape.
- 2-preswap-checkout-kill-legacy (inject=none; fab=3) — the v2026.05.2-baseline variant, **superseded by the reshaped 2-preswap-checkout-kill** (post-086). DELETE.

**ASSESS (the ONE true no-inject CAT-C):**
- 3-postswap-worker-ddl-deadlock (inject=none; fabricates the deadlock state) — no STATBUS_INJECT_AT. Needs a REAL reproduction: a self-failing/concurrent-DDL migration fixture that induces the worker↔migrate DDL lock conflict, OR (if only a product inject point would reproduce it faithfully) **King-flag** (product change = beyond the harness charter, per Q5-2), OR a documented residual as last resort. This is the one case needing per-scenario judgment.

## 2. The kill-arc driver (5a) — the new framework piece
Lives in upgrade-arc-harness.yaml (Q5-1 ✓ — shares install_statbus_at_sha + the B-fixture + signing; NOT a parallel install-recovery mode). The reshaped scenarios MIGRATE from install-recovery-harness.yaml into the arc harness (they now need the post-086 baseline + the signed B-fixture). Distinct from the working/failing arcs (which use the daemon-RUN path); the kill-arc is the daemon-DOWN + `./sb install` inline-dispatch path:
1. **Install A=base_sha** (install_statbus_at_sha + trust the arc signer; reuse arc_prepare_box).
2. **Construct B = A + V** (the arc fixture migration, signed + trusted — reuse the construct job's V + the ephemeral-key signing).
3. **register B** (daemon UP → verifyArtifacts flips docker_images_status='ready').
4. **arc_schedule_daemon_down** (NEW helper): quiesce/stop the upgrade daemon → `./sb upgrade schedule B` (RunSchedule → the persistent daemon-down 'scheduled' row). [Mirrors the proven claim-without-notify daemon-down→schedule pattern.]
5. **arc_install_dispatch_with_inject** (NEW helper): `./sb install` inline-dispatch WITH `STATBUS_INJECT_AT=<class>` (+ the one-shot `STATBUS_INJECT_KILL_AND_REMOVE_FILE` for KillHere, or `STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE` for StallHere) → the kill/stall fires at the REAL inject point during the real dispatched upgrade.
6. **Assert the REAL crash state + recovery** (the flag/row each scenario already asserts; the flag is REAL — written by the real executeUpgrade before the inject — so NO synthetic crash-state needed). Recovery via `./sb install` crashed-recovery / service restart → terminal state.
**Prove ONE CAT-A scenario green** (recommend 2-preswap-checkout-kill — a clean KillHere, simplest). 5a delivers the two helpers + the one green proof.

## 3. Phasing (each phase → architect review → foreman commit → VM-prove green → next)
- **5a** — kill-arc driver (arc_schedule_daemon_down + arc_install_dispatch_with_inject) + ONE CAT-A scenario (checkout-kill) green via the real arc.
- **5b** — CAT-A reshape (the other 4 KillHere scenarios) onto 5a; drop their fabricate calls.
- **5c** — CAT-B reshape (6 stall/watchdog scenarios) onto 5a + the stall knobs; drop fabricate.
- **5d** — CAT-C: reshape the 4 mid-migrate scenarios (SAME swap — existing inject); DELETE deterministic-error (subsumed) + checkout-kill-legacy (superseded); ASSESS worker-ddl-deadlock (self-failing-migration fixture → else King-flag).
- **5e** — DELETE `fabricate_scheduled_upgrade_row` at zero callers (AC#4) + sweep now-unused synth helpers (the crash-flag/in_progress synths, seed_pre_upgrade_snapshot if unused). Confirm: `rg fabricate_scheduled_upgrade_row` = 0.

## 4. AC mapping + King doctrine
- **AC#3** = §1's swap (family-wide fabricate→register/schedule; crash stays real) + DELETE the subsumed deterministic-error.
- **AC#4** = 5e: fabricate_scheduled_upgrade_row deleted at zero callers; no synthetic crash-state fabrication remains (the real inject writes the real flag/state).
- **King doctrine (NO residual):** every fake → real (the swap; crash already real) or DELETED (subsumed/legacy). The mid-migrate "unreproducible-without-fabrication" premise was a FALSE framework-gap belief — the inject points exist (mem #837); no gap to fix there. The ONLY possible residual is worker-ddl-deadlock IF no faithful real path exists → then King-flag (product change) or a DOCUMENTED residual with its reason, never silent.

## 5. Risks / decisions
- **Preserve each scenario's exact crash-shape contract.** The legacy kills encode specific historical wedges (STATBUS-017 cell-e, the rune NO wedge, mid-tx-commit-after-rollback). A reshape MUST hit the same inject class + assert the same crash state — or confirm a real arc covers the contract before deleting. Don't lose regression coverage. (Each phase VM-proves the reshaped scenario green = the contract still holds.)
- **No new product inject sites in §9(5)** (Q5-2): the mid-migrate points exist; worker-ddl-deadlock is the only candidate for a product change → King-flag, do NOT add autonomously.
- **The crash-flag synth retires too:** with a real inject + real `./sb install` dispatch, the flag is written by the real executeUpgrade → AC#4's "no synthetic crash-state" is fully achievable (not just the scheduled-row synth).
- **Migration of scenarios** install-recovery-harness.yaml → upgrade-arc-harness.yaml: the kill-arc scenarios need the arc harness's post-086 + signing; the install-stage (5-*) + boot (1-*) scenarios STAY in install-recovery (they don't reshape). Confirm the workflow split in 5a.
- **Scale:** ~14 reshape + 2 delete + 1 assess. Phase it; one VM-proof per reshaped scenario before the next (the freeze protocol).
