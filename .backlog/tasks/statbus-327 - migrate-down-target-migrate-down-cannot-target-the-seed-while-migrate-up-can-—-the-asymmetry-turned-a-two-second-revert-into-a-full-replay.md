---
id: STATBUS-327
title: >-
  migrate-down-target: migrate down cannot target the seed while migrate up can
  — the asymmetry turned a two-second revert into a full replay
status: To Do
assignee: []
created_date: '2026-08-31 12:13'
labels:
  - cli
  - tooling
dependencies: []
priority: low
type: enhancement
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: reverting a work-in-progress migration from the seed is as cheap as applying one to it. Today it is not: `./sb migrate up` takes --target seed, but `./sb migrate down` has no target flag at all (only --to) and always runs against the default dev connection.

OBSERVED COST (2026-08-31, 308's comment-migration teardown): a WIP migration had been applied to dev AND seed; the ruled removal sequence assumed `migrate down` would revert the seed, but it reverted dev only — leaving the seed AHEAD of HEAD with no file on disk, exactly the state assert-db-at-head and the 313 runner gate exist to catch. The engineer correctly refused the hand-edit escape (deleting the ledger row or hand-running the down SQL against the seed is a manual DB write, and the ledger is trustworthy precisely because nothing edits it by hand) and took the sanctioned path: delete the files, full `./dev.sh recreate-seed` replay — several minutes for what a targeted down would have done in two seconds. The foreman's sequence asserted the seed-targeting premise without checking; the builder caught it at runtime.

THE FIX: give `migrate down` the same --target semantics as `migrate up` (default dev, seed addressable), reusing the existing connection-targeting machinery. The redo verb's constraint discipline (latest-applied-only, WIP-scoped) applies unchanged — down-targeting the seed must not become a backdoor around released-migration immutability; the same guards that protect down today protect it per-target.

WHAT IS ACHIEVED: the edit-migration-then-retreat loop is symmetric and cheap on both databases, and nobody is ever tempted toward the hand-edit escape by a missing flag.
<!-- SECTION:DESCRIPTION:END -->
