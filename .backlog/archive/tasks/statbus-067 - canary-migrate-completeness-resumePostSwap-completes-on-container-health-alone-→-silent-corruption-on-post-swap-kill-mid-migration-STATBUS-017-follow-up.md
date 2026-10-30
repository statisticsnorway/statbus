---
id: STATBUS-067
title: >-
  canary-migrate-completeness: recovery must roll back (not self-heal) when a
  migration committed but its done-record was lost; the two converged tests must
  exercise this
status: Done
assignee: []
created_date: '2026-06-16 21:57'
updated_date: '2026-06-19 15:38'
labels:
  - upgrade
  - recovery
  - data-integrity
  - statbus-017
  - architect-plan
  - follow-up
dependencies: []
priority: high
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
REAL PRODUCT BUG (architect root-caused + adversarially verified 2026-06-16; foreman reviewed). Surfaced by the rc.04 comprehensive run (run 27645059996) once the two STATBUS-017 guards were included (3-postswap-migrate-killed-after-commit, 3-postswap-migration-deterministic-error). PRE-EXISTING — NOT from the rc.04 batch: 062 (6f1b3a02f) touched resumePostSwap RENAME-ONLY, 065 Fix B did not touch resumePostSwap; both guards are HARNESS_SKIP_DEFAULT and never had a green CI baseline (so "regressed" is false). NON-GATING for rc.04.

BUG (Q1): resumePostSwap's convergence canary (service.go:4761 `if containersAtFlagTarget(...)`, plan-rc.66 Item E) declares the upgrade converged on CONTAINER HEALTH ALONE → self-heals the row to 'completed'. A post-swap kill DURING migrate-up leaves containers healthy at target WITH migrations half-applied (committed-but-unrecorded). The proxy "containers healthy at target" is TRUE both when genuinely converged (the rune Apr-24 bookkeeping-only case where forward is correct) AND when killed-mid-migration (where forward is a silent lie) — it cannot distinguish them. So it silently marks a half-migrated DB 'completed' — exactly the corruption STATBUS-017 targets. PRODUCTION-REACHABLE (OOM/power-loss mid-migrate on recovery); latent only because the reproducers are skip-default (heavyweight). Adversarially verified: forward is genuinely wrong here, the scenario's rolled_back expectation is correct.

CONSTRAINT (Q2, BUNDLED — do NOT ship alone): the self-heal UPDATE (service.go:4771) omits log_relative_file_path, which the 'completed' branch of chk_upgrade_state_attributes requires NOT NULL (doc/db/table/public_upgrade.md:45) → SQLSTATE 23514 on the fabricated row. RIGHT NOW that 23514 is a LOAD-BEARING SAFETY NET — the only thing stopping the wrong-forward completion from succeeding. Q2 (set log_relative_file_path) must NOT ship without Q1 — it would turn the caught error into silent production corruption. NOT from_commit_sha (absent from the constraint; chk_upgrade_from_commit_sha_is_full_hex explicitly permits NULL).

FIX DIRECTION (recovery-code DESIGN change, not a quick patch): gate the canary's self-heal-to-completed on a positive "no pending migrations" probe (DB migration-tracking vs disk migration set); if incomplete → fall through to rollback/continuation, never self-heal to completed. AND set log_relative_file_path in the completed UPDATE (from the progress log resumePostSwap reopened at service.go:4727-4730). Q1+Q2 together. OWNER: architect (design) → engineer (execute) → foreman review.

KING DECISION PENDING: include in rc.04 vs priority post-rc.04 follow-up. Foreman recommendation: follow-up (pre-existing + latent; don't block rc.04) — but it is a real corruption risk, so it should be the priority item after rc.04.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
IMPLEMENTATION (architect, engineer-ready; MUST validate with the skip-default reproducer — do not land blind).

SMOKING GUN: the convergence canary (service.go:4761, plan-rc.66 Item E) short-circuits STATBUS-017's OWN landed deferral (service.go:1675-1697 → recoverFromFlag :1708 → the Resuming/PostSwap one-shot latch's snapshot-restore rollback). Both landed; they conflict — the canary fires first on "containers healthy at target" (applyPostSwap ran `docker compose up` before the migrate kill) and self-heals to completed FORWARD, skipping the rollback STATBUS-017 routed the half-applied migration to.

Q1 — GATE (service.go:4761): inside `if ok, mismatched := d.containersAtFlagTarget(ctx, flag); ok {`, add `pending, perr := migrate.HasPending(d.projDir)` (cli/internal/migrate/migrate.go:545 — on-disk migration files vs db.migration applied versions). The inject leaves the migration committed-but-UNRECORDED → absent from db.migration → HasPending=true. If perr != nil || pending → do NOT self-heal; log + fall through to the continuation (service.go:4864 — re-acquire flock → applyPostSwap → migrate up re-hits "relation already exists" → postSwapFailure → rollback → rolled_back = STATBUS-017's intended terminal). Else (genuine convergence, the rune Apr-24 SDNOTIFY case) → self-heal via the Q2 UPDATE.

Q2 — CONSTRAINT-SAFE genuine-convergence path (service.go:4771, BUNDLED with Q1): the self-heal UPDATE must set log_relative_file_path so 'completed' satisfies chk_upgrade_state_attributes: `UPDATE public.upgrade SET state='completed', completed_at=now(), docker_images_status='ready', error=NULL, log_relative_file_path=COALESCE(log_relative_file_path,$2) WHERE id=$1 AND state='in_progress'`, $2 = the progress log's relative path (resumePostSwap holds `progress`, reopened at service.go:4727-4730 — add a relative-path accessor). COALESCE so a real run's existing path isn't clobbered. Q2 MUST NOT ship without Q1 (it would let the wrong-forward self-heal SUCCEED, removing the 23514 safety net → silent corruption).

VALIDATION CAVEAT (load-bearing): Q1 routes the pending case to the continuation (applyPostSwap → migrate-up-fails → postSwapFailure → rollback). The operator observed the row ending in_progress (not rolled_back) in run 27645059996 — so the continuation's terminal-state for THIS exact case must be VALIDATED with the skip-default reproducer 3-postswap-migrate-killed-after-commit (a paid-VM run), not assumed; it may itself need a touch to guarantee rolled_back. ONE harness iteration required by design.

OWNER: architect (design done) → engineer (execute) → foreman review → tester validate with the reproducer. NON-gating for rc.04; reopen STATBUS-017 as the priority post-rc.04 item if the King rules defer.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
HARNESS PREREQ ALREADY IN PLACE (foreman, fc742bd4f, 2026-06-17): both reproducers (3-postswap-migrate-killed-after-commit, 3-postswap-migration-deterministic-error) now call `quiesce_upgrade_service "$VM_NAME" >&2` inside _fabricate_in_progress_row, immediately before fabricate_scheduled_upgrade_row. This closes the fabricate→in_progress-UPDATE window where the running upgrade service could claim the scheduled row — removing a race confound from the eventual canary re-validation. NOTE for the engineer/tester: this shifted the scenario line numbers cited in the Implementation Plan by ~+5 (the manual in_progress UPDATE block moved down); RE-READ the scenario rather than trusting the cited line refs. The Q1/Q2 FIX itself is in cli/internal/upgrade/service.go (4761/4771) — unaffected by the scenario shift.

KING RULED 2026-06-17: FIX NOW — include the canary fix in rc.04 (overrode the foreman/architect defer recommendation). The King is driving the architect directly on the Q1+Q2 implementation. Flow: architect writes the exact Q1+Q2 old_string/new_string vs current cli/internal/upgrade/service.go → engineer applies → architect reviews byte-level → foreman commits + pushes. Validation: 3-postswap-migrate-killed-after-commit promoted out of skip-default for the combined re-run (quiesce already in from fc742bd4f). EXPECTATION (King-accepted): the rolled_back terminal must be confirmed empirically (operator saw in_progress) — first reproducer run may land short and need one follow-up touch; that is the fix-now cost, expected not a regression. Sequencing: carve-out (55cb5c959, committed+pushed) + canary fix both land → ONE comprehensive re-run validates the gating set + the promoted reproducer together.

RUN B RESULT (foreman, 2026-06-17, run 27674217081): the canary fix did NOT produce rolled_back. BOTH repros failed IDENTICALLY with the COMPLETED outcome (architect's 3rd case = re-diagnose, NOT a continuation touch):
- 3-postswap-migrate-killed-after-commit (line 445): expected rolled_back, ACTUAL=completed; db.migration max_version=20260616104500; sentinel_object_present=true; NRestarts=0; flag ABSENT.
- 3-postswap-migration-deterministic-error (line 388): expected rolled_back, ACTUAL=completed; db.migration max_version=20260616104500.

The Q1 gate did NOT fire → else-branch self-healed to completed. HasPending (migrate.go:545-562, read by foreman) is a clean check (on-disk files vs applied set); it returned FALSE → at the canary check EVERY on-disk migration was ALREADY recorded in db.migration.

ALARM-REVERSAL (ground truth = the run): the design ASSUMED the migration is committed-but-UNRECORDED at the canary (HasPending=true). Empirical is the OPPOSITE — recorded + sentinel present → the DB looks CONSISTENT → `completed` looks CORRECT, not corrupt. Either (a) recovery (boot-migrate-up/STATBUS-017) reconciles the half-applied migration → completed is correct → the canary 'bug' is NOT real → REVERT the canary fix 1e02a1797 (it would wrongly defer genuine convergence) + re-expect the scenarios; OR (b) the DB is genuinely half-applied invisibly to HasPending → gate needs a different signal. Routed to architect for rigorous re-diagnosis (a 'no-bug-after-all' conclusion requires adversarial verification, not acceptance); engineer available to instrument (dump db.migration + on-disk set + HasPending result at the canary). Full log: tmp/runB-failed.log.

NOTE: the canary fix is INERT for genuine-convergence (HasPending=false → self-heal, unchanged), so it does not affect RUN A's gating scenarios — RUN A (gate, run 27675235157) triggered in parallel, valid regardless of this re-diagnosis.

RE-DIAGNOSIS COMPLETE + FOREMAN-VERIFIED (2026-06-17): BRANCH (b) — the reproducer is broken (topology infidelity), NOT branch (a) (no-bug). KEEP the canary fix 1e02a1797; DO NOT revert.

VERIFIED EVIDENCE (foreman checked tmp/runB-failed.log + code directly, not just architect's word):
- :7674 the synthetic migration is version 20991231235959, committed as a SEPARATE tracked commit ON TOP OF pre-upgrade — NOT inside flag.CommitSHA.
- :7722 recovery's deferred checkout moves the tree to flag.CommitSHA=73ea5210, which does NOT contain that file → the migration file is STRIPPED from migrations/.
- :7724 canary logs 'no pending migrations — self-healing' because listMigrationFiles no longer sees the stripped file → HasPending=FALSE → else-branch self-heals to completed.
- :7793 sentinel_object_present=true, max_version=20260616104500 (a normal migration, not the far-future sentinel): the sentinel TABLE stays applied + unrecorded + FILE-LESS — an orphaned-object inconsistency HasPending (file-vs-record) structurally cannot see.
- migrate.go:825-835 confirms the PRODUCTION bug is REAL verbatim (committed-but-unrecorded migration → forward-recovery fails 'relation already exists' → only rsync-restore recovers).

WHY THE FIX IS CORRECT (production topology): in prod the migration is part of the TARGET commit = flag.CommitSHA. Recovery checks out flag.CommitSHA → file PRESENT → HasPending=TRUE → Q1 defers → rollback. The reproducer's backwards topology (migration ABOVE flag.CommitSHA → stripped) cannot occur in production. Both repros share the flaw (deterministic-error 'tracked on top of pre-upgrade' = same shape).

DO NOT change the gate to an orphaned-object signal — that file-less state is a reproducer artifact, not a production case; HasPending (file-vs-record) is correct.

NEXT: fix the REPRODUCER, not the gate — make the synthetic migration present in the tree at flag.CommitSHA at the canary (align migration commit / flag.CommitSHA / container tags / binary commit). Architect designing the exact reproducer-fix + canary-point instrumentation dump (db.migration, on-disk migrations, HasPending, HEAD vs flag.CommitSHA, container tags, sentinel) in ONE change → engineer applies → foreman commits + pushes + runs. Canary fix is correct-by-analysis (verified) but NOT empirically proven green until a faithful reproducer runs rolled_back — per the King's run-is-the-oracle principle, the canary is not done until then. Test-harness only; still needs commit→push→run.

DONE (foreman-verified 2026-06-19): self-heal canary implemented at resumePostSwap (cli/internal/upgrade/service.go:5053 — containersAtFlagTarget && !migrate.HasPending → self-heal to completed; HasPending → roll back, the 'committed-but-record-lost → rollback not self-heal' requirement). The 'two converged tests must exercise it' is tracked in STATBUS-071 §9(5) 5d (after-commit reshape).
<!-- SECTION:NOTES:END -->
