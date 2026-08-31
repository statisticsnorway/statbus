---
id: STATBUS-329
title: >-
  migrate-down-released-guard: down reverts released migrations with nothing
  standing in the way — the cut-gate guards files while the hazard is in the
  ledger
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-31 12:51'
updated_date: '2026-08-31 19:42'
labels:
  - cli
  - tooling
  - release
dependencies: []
priority: medium
type: bug
ordinal: 322000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a destructive capability is guarded at the point of destruction, not by hoping something downstream notices. `migrate down` can revert a RELEASED migration in a database and no guard exists — found during 327 (which made the seed reachable in two keystrokes) and ruled TICKET by the architect (2026-08-31).

WHY THE EXISTING GATE DOES NOT COVER IT (verified, not assumed): checkMigrationImmutability diffs the migrations/ DIRECTORY between prevTag and HEAD (release.go:898, via checkImmutabilityGate at :86, check 3). It compares FILES IN GIT and never observes database state. A migrate down reverts a migration in a database and leaves the file untouched — the gate sees nothing. The reverted state is indistinguishable from a pending one (file present, ledger row gone), so on dev the next migrate up self-corrects, which is why this never bit.

THE SEED IS WHERE IT STOPS SELF-CORRECTING: if a new seed artifact is built by restoring the previous artifact and applying subsequent migrations (the 312 path), then migrate down --target seed against a released migration followed by a seed build publishes an artifact MISSING that migration. Every installation born from that image inherits the gap, invisibly to the cut-gate's file diff.

THE REFUSAL SHAPE (architect's design):
1. migrate down refuses when the target migration is RELEASED — present in the previous release tag's migrations/ directory.
2. REUSE checkMigrationImmutability's own definition of "released" and its pickPrereleasePredecessor tag resolution — one shared definition; two independently-computed answers to "is this released" would drift silently.
3. Refuse on BOTH targets, not seed-only: reverting a released migration on dev means testing against a schema no fleet box has. The legitimate case (reproducing a bug against an older schema) is what the override is for.
4. The refusal message names three things: which migration; that it is released and in which tag; and, when the target is the seed, that proceeding would publish an artifact missing it.
5. Override: INTENTIONALLY_REVERT_RELEASED_MIGRATION=1, matching the IntentionallyFixBrokenImmutableMigration style — the name is the guard; it must make a cold agent stop and escalate, never self-authorize (FORCE=1-style naming explicitly rejected).

OPEN DETAIL ON RECORD (stated, not guessed): computeSeedDigest takes the migration ledger as one of its three inputs, so a reverted migration WOULD move the digest — but whether the seed pin compares against something predating the same build was not established. Recorded as an open detail, not an assumed backstop: "something downstream might notice" is not a guard.

WHAT IS ACHIEVED: reverting released history requires saying so in words no one can mistake for routine, on either database — and the published seed can never silently lose a migration through the ergonomic path 327 opened.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 migrate down (and down all, and --to ranges crossing the boundary) refuses when the target migration exists in the previous release tag's migrations/ directory, on BOTH dev and seed targets
- [ ] #2 The released-definition and tag resolution are SHARED with checkMigrationImmutability/pickPrereleasePredecessor — no second implementation of 'is this released'
- [ ] #3 The refusal message names the migration, the release tag containing it, and (seed target) the missing-from-published-artifact consequence
- [ ] #4 INTENTIONALLY_REVERT_RELEASED_MIGRATION=1 bypasses with a loud acknowledgment; no other bypass exists
- [ ] #5 Tests: released migration refused on both targets; WIP migration passes unchanged; override proceeds; the computeSeedDigest open detail is resolved and recorded (does the seed pin catch a reverted-migration build or not)
<!-- AC:END -->
