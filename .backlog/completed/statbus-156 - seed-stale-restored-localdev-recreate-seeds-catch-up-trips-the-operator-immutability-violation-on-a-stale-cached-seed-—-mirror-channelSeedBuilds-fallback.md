---
id: STATBUS-156
title: >-
  seed-stale-restored-localdev: recreate-seed's catch-up trips the operator
  immutability violation on a stale cached seed — mirror channelSeedBuild's
  fallback
status: Done
assignee:
  - mechanic
created_date: '2026-07-11 20:31'
updated_date: '2026-07-12 03:21'
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
- [x] #1 A stale cached seed (recorded hash predating a merged retroactive edit, clean working tree) auto-falls-back to the full replay with a loud line naming the cause — no operator immutability violation
- [x] #2 A genuinely edited released migration in the working tree still hard-refuses exactly as today
- [x] #3 The distinction is typed (ErrStaleRestoredMigration), never inferred from error text
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED 8f4f1a77a (2026-07-12), 6 files +198/−10, architect SHIP as-built. The fix mirrors channelSeedBuild's typed fallback as pre-named: release.FileIsDirty (git diff --quiet with a rev-parse is-inside-work-tree PRECONDITION — git diff exits 1 for both "dirty" and "no repo", an ambiguity the mechanic caught by writing the no-repo test FIRST and watching the draft fail); the channelLocalDev released-tag branch returns the typed ErrStaleRestoredMigration ONLY when dirtiness is positively false, all uncertainty falling through to the original refusal byte-identical (AC-2 by construction); new dedicated ExitStaleRestoredMigration=21, deliberately separate from the 046 A/B/C production classifier surface; dev.sh's recreate-seed keys on rc 21 numerically (AC-3 typed, never text) with the loud cause line before the existing FULL_REPLAY exec pattern. LIVE-PROVEN on real Postgres + git (scratch clone of statbus_test_template, ledger corrupted there only, trap-driven cleanup verified, .env restored via canonical config generate): clean file + stale ledger → typed error rc=21; the SAME migration (20260218215337, the original incident's) deliberately dirtied → the ORIGINAL immutability-violation text, rc=1 (AC-1 + AC-2 live). The wrapper's exec hop judged review-sufficient on three legs (six lines reusing a production-proven sibling pattern; the novel signal live-proven; failure mode = the old refusal, fail-safe; structurally loop-free since FULL_REPLAY never enters the catch-up). Cross-surface note recorded: if a production boot-migrate ever surfaces exit 21, the daemon routes it through the same unclassified branch as before (unchanged), and the real finding would be a 072 re-stamp conveyance gap. Evidence: tmp/mechanic-156-verify.log.
<!-- SECTION:FINAL_SUMMARY:END -->
