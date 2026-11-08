---
id: STATBUS-594
title: Unreleased combined-import migrations sort after the published release
status: In Progress
assignee: []
created_date: '2026-11-08T10:51:00Z'
updated_date: '2026-11-08T11:07:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 510204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Exact combined candidate 9c7aa9a Go CI 42472515430 fails TestNewMigrationsSortAfterPreviousRelease. Five unpublished STATBUS-591 migration pairs predate published v2026.11.2 maximum version 20261107200300, so fresh replay and incremental upgrades do not share a valid release order. Rename only those unreleased pairs without changing SQL bodies or released files, then prove correct fresh and incremental behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The existing migration release-order regression is RED on 9c7aa9a and GREEN after the repair, with all ten unpublished SQL file bodies byte-identical and released migrations unchanged.
- [ ] #2 Fresh full replay and v2026.11.2 baseline plus incremental migrations reach equivalent schema and required import/recovery behavior, with original dependency order preserved.
- [ ] #3 Local seed and template transition is non-destructive and verified, complete doc/db and type generation introduce no unintended drift or deletions, and the full SQL and Go regressions pass.
- [ ] #4 The corrected exact SHA is committed and pushed, CI status and conclusion are explicitly verified, and named candidate guest gates pass before release-candidate acceptance. Next stable remains held for owner review.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Root hypothesis/prototype tmp/journal.md. Actual unchanged regression RED tmp/591-migration-order-red.log. Read-only rename and body-hash prototype PASS tmp/591-migration-order-prototype.log. Original frozen 9c7 SQL validation passed all134 shared plus isolated094/143, tmp/591-final-fast.log exit0. No RC was cut from the Go-RED source.

2026-11-08 11:06 UTC: Existing release-order regression RED on9c7 and GREEN after five unreleased pair renames to20261108104710..14. tmp/594-body-equivalence.log proves all10SQL bodies and876released files byte-identical. Actual fresh442 and released437+5 incremental runner executions passed501s. Complete schema including grants/owners identical;71seed/domain tables and queue rows match with5761actual declared audit-clock values per run validated within replay window and normalized only on19explicit tables, all validity dates preserved (tmp/594-replay-equivalence.log). Full CLI Go PASS176.5s tmp/594-go-final.log. Exclusive-lock local canonical seed/template safely rebuilt from verified fresh replay, old DBs archived, clone verifies442/max20261108104714, no existing DB deleted/session terminated/ledger edited (tmp/594-local-seed-replace.log). AC2/3 remain open until corrected full SQL behavior regression completes. Documentation/types generation, exact-SHA CI and named guest gates still pending, no RC cut.

11:07 UTC: complete ./dev.sh generate-doc-db and ./sb types generate both exit0. No doc/db deletions and no type changes. Only generated drift was the already characterized six redundant aliases in non-first UNION arms of public_statistical_unit_def; full diff retained tmp/594-doc-deparser-only.diff and that single owned generated file restored. Dirty-migration freshness stamps correctly withheld, clean post-commit regeneration remains required.
<!-- SECTION:NOTES:END -->
