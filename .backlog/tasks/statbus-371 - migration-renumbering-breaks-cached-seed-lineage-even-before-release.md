---
id: STATBUS-371
title: >-
  migration renumbering breaks cached seed lineage even before release
status: To Do
assignee: []
created_date: '2026-09-16 22:34'
updated_date: '2026-09-16 22:34'
labels:
  - migrations
  - ci
  - fail-fast
dependencies: []
priority: high
type: task
ordinal: 9
---

## Description

A migration filename/version is part of the seed-cache chain as soon as a cache
has recorded it. "Never released" does not make renumbering safe.

STATBUS-347 migration `20260903205636` was retimestamped to
`20260907120000` in `f6d249b62`. Niue's stale cached seed still contained the
old version and its `rollback_finish_pending_at` column. The eager content-hash
check ignored file-less orphan ledger rows, so restore accepted the cache and
full replay attempted the renumbered migration against the already-present
column. pg_regress then failed every commit since rc.11 with
`column rollback_finish_pending_at already exists`.

## Observed repair (2026-09-16)

- `aaaaee881`: fail-closed cache compatibility preflight before `pg_restore`.
- `23b3993ad`: rejected development cache falls back to full replay.
- Niue pg_regress run `35116209731`: stale cache rejected, full replay used,
  all 100 tests passed.

These commits repair cache consumption. They do not yet prevent a migration
renumber from entering the prerelease line.

## Architect decision required

Choose and build the forward guard at the prerelease gate. It must reject a
candidate when migration history renames or removes a version that can exist in
any retained seed/cache chain, even if no named release contains that version.
The invariant and authoritative comparison base are not yet designed. Do not
close this ticket on the restore fallback alone.
