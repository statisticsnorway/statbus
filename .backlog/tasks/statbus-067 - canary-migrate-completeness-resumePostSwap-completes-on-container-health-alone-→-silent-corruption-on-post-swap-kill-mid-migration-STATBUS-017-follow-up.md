---
id: STATBUS-067
title: >-
  canary-migrate-completeness: resumePostSwap completes on container-health
  alone → silent corruption on post-swap kill mid-migration (STATBUS-017
  follow-up)
status: To Do
assignee: []
created_date: '2026-06-16 21:57'
updated_date: '2026-06-16 22:36'
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
<!-- SECTION:NOTES:END -->
