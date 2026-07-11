---
id: STATBUS-156
title: >-
  seed-stale-restored-localdev: recreate-seed's catch-up trips the operator
  immutability violation on a stale cached seed — mirror channelSeedBuild's
  fallback
status: To Do
assignee: []
created_date: '2026-07-11 20:31'
labels:
  - dev-tooling
  - seed
  - fail-fast
dependencies: []
references:
  - cli/internal/migrate/migrate.go
  - dev.sh
  - STATBUS-116
  - STATBUS-126
priority: medium
ordinal: 157000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a stale cached seed never masquerades as an operator's immutability violation — the machinery distinguishes "you edited a released file" (refuse) from "your cache predates a legitimately-merged edit" (auto-recover).
> STAGE: dev tooling. FOUND: 2026-07-11, blocking the STATBUS-154 test run; diagnosed from source by the engineer.
> COMPLEXITY: engineer-small; the fix shape is pre-named (mirror an existing mechanism), architect confirms before build.

OBSERVED: ./dev.sh recreate-seed restored the cached .db-seed/seed.pg_dump (May-24 vintage) and its catch-up migrate hard-refused: "immutability violation: migration 20260218215337 ... is in release v2026.03.0 and its file bytes have changed since apply" — but the working tree was CLEAN; the mismatch source was the CACHE predating the legitimately-merged retroactive edit 8b5912a9a (the seed-drift fix). The operator-facing error accuses an edit that never happened.

THE MECHANISM (engineer, from source): the bless (STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION) is honored only in channelRelease (migrate.go:1735-1758, by design — trust the cut gate). recreate-seed's catch-up runs under channelLocalDev (:1780-1797), which for a released-tag migration always hard-refuses — correct for its intended case (a human editing a released file). The GAP: channelLocalDev conflates two mismatch sources; channelSeedBuild already distinguishes the stale-restored case via the typed ErrStaleRestoredMigration → caller falls back to a FULL rebuild (migrate.go:1728-1734, STATBUS-116 Part C) — the localDev recreate-seed catch-up has no equivalent.

WHY THE CACHE GOES STALE STRUCTURALLY: ./sb db seed fetch pulls the seed image tagged by the CURRENT commit_short (seed.go:109-115); when HEAD has no published image, recreate-seed falls back to the cached dump — which never refreshes on its own. Every developer's cache goes stale on the next retroactive edit; everyone hits this once.

FIX SHAPE (pre-named, architect confirms): mirror channelSeedBuild — the recreate-seed catch-up detects ErrStaleRestoredMigration and auto-falls-back to the FULL_REPLAY path with one loud line naming why ("cached seed predates a merged edit to <migration> — replaying from scratch"). The operator refusal for a genuinely edited working-tree file stays untouched. WORKAROUND until fixed: FULL_REPLAY=1 ./dev.sh recreate-seed (the documented override, dev.sh:1583-1586).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A stale cached seed (recorded hash predating a merged retroactive edit, clean working tree) auto-falls-back to the full replay with a loud line naming the cause — no operator immutability violation
- [ ] #2 A genuinely edited released migration in the working tree still hard-refuses exactly as today
- [ ] #3 The distinction is typed (ErrStaleRestoredMigration), never inferred from error text
<!-- AC:END -->
