---
id: STATBUS-411
title: >-
  The installer tells its own unfinished database from a pre-1.0 database with
  data
status: Done
assignee: []
created_date: '2026-09-24 15:59'
updated_date: '2026-10-20 20:53'
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

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When the installer finds a database without StatBus's upgrade table, it tells correctly whether that is its own unfinished work, which it simply continues, or an old StatBus database with real data, which it refuses to touch.

### Zoom out
"No `public.upgrade` table" has two very different meanings:
- **Our own unfinished install:** the database container created an empty cluster, or the install stopped part-way through migrations. Continuing is correct and loses nothing.
- **A pre-1.0 StatBus database:** it holds a country's register. Writing over it would destroy data, so the installer refuses and points to the manual upgrade path.

The two are told apart by how the database was built, not by the current date or by guessing from table counts. Migration versions are permanent provenance: a version applied today from an old release is still an old version. So a database counts as our unfinished install only if it has no migrations and no application tables, or if every applied migration is newer than the one that introduced `public.upgrade`. Anything else, including application tables with no migration history, is pre-1.0. When unsure, the installer refuses.

STATBUS-408 is the same rule seen from an interrupted first install; it owns proving the resume path.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** the operator removed `statbus-local-db-data`, ran `./sb restart all` (which created an empty database), then `./sb install`. It was refused: `Detected install state: legacy-no-upgrade-table ... pre-1.0 install detected (public.upgrade table absent)` (`tmp/finland-answers-4.txt:66-89`). Detection then treated every reachable database without `public.upgrade` as pre-1.0.
- **Shipped (v2026.09.3):** `0a3f2ff80` continues an install stopped after the database was created. `3c76d6323` classifies from migration provenance: `SchemaHistory.IsUnfinishedFreshInstall` against `upgradeTableMigrationVersion = 20260311174120` (`cli/internal/install/state.go`). `da2be2fde` and `f786999bd` refuse unclassifiable states and require proof that the database is really unavailable. The operator sees `The database exists but setup stopped before it was finished. Continuing where it stopped.` or `This installation is too old for automatic repair. Follow the documented manual upgrade path.`
- **Proof, unit:** `TestDetectWith` (`cli/internal/install/state_test.go`) covers init-db only and post-upgrade-era-only history as unfinished; application schema without history, old-release migrations, old migrations applied today and enterprise-only schema as pre-1.0; and a database with `public.upgrade` never consulting history. `TestParseSchemaHistory` covers the probe. Green 2026-10-15.
- **Proof, real box:** `5-install-interrupted-first-run.sh` (see STATBUS-408) shows the continue path. No real-box scenario exercises the refusal path with real legacy data.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the detection policy is the doc comment at the top of `state.go`.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A database with no migrations and no application tables, or whose every applied migration is newer than the one that introduced `public.upgrade`, is classified as an unfinished install and continued (`TestDetectWith` fresh-db-incomplete cases)
- [x] #2 A database without `public.upgrade` that has application tables without migration history, or any migration at or before `20260311174120`, is classified pre-1.0 and refused before anything is written (`TestDetectWith` legacy cases)
- [x] #3 On a real box, an init-db-only database (an install stopped after Services, the same shape Finland's `./sb restart all` produced) is continued through Seed and Migrations to a serving site (`5-install-interrupted-first-run.sh`, rc.17 LXD PASS, owned by STATBUS-408)
- [x] #4 [Owner] Decide whether a real-box proof that a pre-1.0 database with sentinel data is refused and left unchanged is required, and record it in Implementation Notes. No: check this and set Done. Yes: add that scenario as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green locally on master, 2026-10-15 (`go test ./internal/install/`).
- **AC3:** rc.17 LXD PASS (2026-09-29 audit, `ea170989e`).
- **Superseded criteria:** the restyle named `state_markers_test.go::TestDetectWithSchemaAndSeedMarkers`, `5-install-init-db-only-recovery.sh` and `5-install-legacy-data-preservation.sh`, none written. Its proposed discriminator (`to_regclass('public.statistical_unit')` plus a `db.migration` row count) was superseded by migration provenance, which also refuses an old release replayed today.

### Owner rule applied 2026-10-20: no extra proof required
The fix is in, tested (Go and LXD scenario) and green through the release gates. The optional extra real-box proof is not required. Revisit only if the issue appears again in real use.
<!-- SECTION:NOTES:END -->
