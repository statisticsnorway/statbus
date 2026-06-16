---
id: STATBUS-067
title: >-
  canary-migrate-completeness: resumePostSwap completes on container-health
  alone → silent corruption on post-swap kill mid-migration (STATBUS-017
  follow-up)
status: To Do
assignee: []
created_date: '2026-06-16 21:57'
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
