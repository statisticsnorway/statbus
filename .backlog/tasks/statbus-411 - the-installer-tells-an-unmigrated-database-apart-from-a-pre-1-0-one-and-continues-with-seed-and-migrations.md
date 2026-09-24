---
id: STATBUS-411
title: The installer continues an initialized database through seed and migrations while preserving legacy data
status: In Progress
assignee: []
created_date: '2026-09-24 15:59'
updated_date: '2026-09-24 18:44'
labels:
  - release-bug
  - install
  - recovery
  - database
dependencies: []
priority: high
type: bug
ordinal: 361100
---

## Status 2026-09-24

**In Progress.** `3c76d6323`, `474cf6119`: `cli/internal/install/state.go` and `state_test.go::TestDetectWith` distinguish init-db-only and legacy by schema/migration provenance (#1 partly). #2-3 named disposable-VM scenarios are absent. **Remaining:** prove seed/migration resumes a bare initialized volume and legacy sentinel data survives a refusal unchanged.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An init-db-only database with no `public.upgrade`, null `to_regclass('public.statistical_unit')`, and missing or empty `db.migration` is a first installation ready for seed and migrations. A database with `public.statistical_unit` present or at least one applied `db.migration` row but no `public.upgrade` is legacy, and its data is preserved with manual-upgrade guidance. STATBUS-408 shares this exact discriminator for interrupted first installation.

## Evidence, 2026-09-24

Current state detection treats every reachable database without `public.upgrade` as legacy (`cli/internal/install/state.go:138-148` at master `7a9cf707e`), with current fake-probe coverage at `cli/internal/install/state_test.go:46-77`. Applied migrations are recorded in `db.migration` (`cli/internal/migrate/migrate.go:1-5`), and the existing seed-gate matrix defines missing, empty, and populated ledger semantics (`cli/cmd/seed_gate_test.go:25-58`), both at master `7a9cf707e`. Finland recreated a fresh database volume and received the legacy refusal (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:69-89`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `cli/internal/install/state_test.go::TestDetectWith` plus `new: cli/internal/install/state_markers_test.go::TestDetectWithSchemaAndSeedMarkers` classifies init-db-only, both conflicting fake-probe edges, established legacy, and migrated states using `public.statistical_unit` presence and `db.migration` row count.
- [ ] #2 `new: test/install-recovery/scenarios/5-install-init-db-only-recovery.sh` uses a disposable volume, observes seed and migrations complete, and finishes with every required service ready.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-legacy-data-preservation.sh` creates representative legacy data, observes manual-upgrade guidance, and proves every sentinel row remains unchanged.
<!-- AC:END -->
