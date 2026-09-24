---
id: STATBUS-408
title: An interrupted first installation resumes from its first incomplete step
status: In Progress
assignee: []
created_date: '2026-09-24 15:46'
updated_date: '2026-09-24 18:44'
labels:
  - release-bug
  - install
  - recovery
  - database
dependencies:
  - STATBUS-411
priority: high
type: bug
ordinal: 361000
---

## Status 2026-09-24

**In Progress.** `474cf6119`: `cli/internal/install/state.go`, `state_test.go`, and `cli/cmd/install_detection_test.go` implement first-install vs legacy marker classification (#1-2 via equivalent tests). #3-4 named `5-install-interrupted-after-database-created.sh` are absent. **Remaining:** preserve a sentinel and volume across interrupted step-eight rerun, then prove full service readiness on a disposable VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A rerun classifies a reachable database as an interrupted first installation when `public.upgrade` is absent, `to_regclass('public.statistical_unit')` is null, and `db.migration` is missing or contains zero applied rows. It resumes the first incomplete persisted step and preserves the original database volume and its data. A database with no `public.upgrade` but with either `public.statistical_unit` present or at least one `db.migration` row is classified as legacy and preserved for STATBUS-411 guidance.

## Evidence, 2026-09-24

Current detection returns legacy whenever the database is reachable and `public.upgrade` is absent (`cli/internal/install/state.go:138-148` at master `7a9cf707e`). Applied migrations are recorded in `db.migration` (`cli/internal/migrate/migrate.go:1-5`), and the existing seed gate distinguishes a missing table, an empty table, and one or more applied rows (`cli/cmd/seed_gate_test.go:25-58`), both at master `7a9cf707e`. On the disposable VM, a step-8 interruption left the original volume reachable without seed or migrations and every rerun was refused as legacy (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:45-48,163-175`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/internal/install/state_markers_test.go::TestInterruptedFreshMarkers` classifies absent `public.upgrade`, null `to_regclass('public.statistical_unit')`, and missing or empty `db.migration` as interrupted first installation.
- [ ] #2 `new: cli/internal/install/state_markers_test.go::TestLegacyMarkerEdges` classifies both fake-probe edges, `public.statistical_unit` present with no applied migration row and schema absent with at least one `db.migration` row, as legacy requiring preservation.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-interrupted-after-database-created.sh` fails after database creation, writes a sentinel row before interruption, reruns installation, and observes resume from the first incomplete step with the volume and sentinel preserved.
- [ ] #4 `new: test/install-recovery/scenarios/5-install-interrupted-after-database-created.sh` reaches ready services and records the final classification markers.
<!-- AC:END -->
