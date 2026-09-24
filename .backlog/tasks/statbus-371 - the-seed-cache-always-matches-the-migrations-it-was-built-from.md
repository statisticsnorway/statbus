---
id: STATBUS-371
title: The seed cache always matches the migrations it was built from
status: To Do
assignee: []
created_date: '2026-09-16 22:34'
updated_date: '2026-09-24 14:53'
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

## Reconciliation 2026-09-23

Classification: OPEN. Evidence: invariant is documented but no seed-lineage guard/repair implementation was found. No part of the item's own done-when is complete beyond any design already recorded above.

## Implementation note 2026-09-24

Provisional, owner to confirm: the authoritative retained lineage is the union of migration versions visible on first-parent Git history after the previous release baseline. Every master push is eligible to publish a commit-addressed seed, so this is a deterministic, fail-closed over-approximation of versions that may remain in caches even when no release tag contains them.

Rejected alternative: query the set of seed tags currently present in GHCR. Registry state is mutable and network-dependent; deleting or expiring an image would erase the evidence used by the release guard.

The prerelease preflight and prerelease tag validator now reject a candidate that removes or renumbers any version in that lineage. The diagnostic identifies the version, first commit, and original path, and directs the operator to restore the version and add a forward migration.

## North star

The seed cache is keyed by the exact migration lineage it was built from. When migrations are renumbered, the cache is rebuilt from the new lineage before anything uses it.

## 2026-09-24 status

The seed lineage guard is merged. The owner requested an explanation of the
authoritative-lineage choice, so that decision remains **OPEN**. Next step:
explain why the first-parent post-release-baseline union is the authoritative,
deterministic fail-closed source rather than mutable registry state, then
record the owner's confirmation.
