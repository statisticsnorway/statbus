---
id: STATBUS-166
title: >-
  restamp-conveyance: a retroactively-edited released migration re-stamps the
  production ledger via a declared old→new hash conveyance — the exit-21 remedy
  the upgrade path lacks
status: To Do
assignee:
  - '@engineer'
created_date: '2026-07-12 15:25'
labels:
  - upgrade
  - migrations
  - production
  - fail-fast
dependencies: []
references:
  - cli/internal/migrate/migrate.go
  - cli/internal/release/immutability.go
  - doc-014
  - STATBUS-072
  - STATBUS-156
  - STATBUS-123
priority: high
ordinal: 167000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a legitimately-merged retroactive edit to a released migration reaches every deployed box through the NORMAL upgrade path — the ledger re-stamps itself from a declared, auditable conveyance; the immutability refuse keeps its full teeth for everything undeclared.
> STAGE: production upgrade path. FOUND: 2026-07-12 — the dev-slot deploy (row 323154) auto-rolled-back on `sb migrate up` exit 21: migration 20260218215337's ledger content_hash (cd82bc76) ≠ on-disk hash (71befa05) after the 8b5912a9a retroactive seed-drift fix. Every slot whose DB applied the old bytes fails identically; STATBUS-123's deploy sequence is blocked at the dev gate.
> COMPLEXITY: engineer-scoped; fix shape architect-ruled (below). HIGH — blocks all slot deploys.

THE DECISIVE STRUCTURAL FACT (rules out the obvious alternative): a "ledger repair migration" is DEAD by construction — eagerContentHashCheck refuses (exit 21) BEFORE `migrate up` applies anything, so a repair shipped AS a migration can never run. The remedy must live in the check itself.

RULED SHAPE (architect, 2026-07-12) — implement STATBUS-072's re-stamp conveyance (doc-014), scoped to the declaration mechanism:

1. DECLARATION FILE, committed with any retroactive edit: `migrations/intentional-restamps.jsonl` — one line per conveyance: {version, old_sha256, new_sha256, reason, ticket}. The name carries the intent (the durable sibling of STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION — a bless is always explicit, named, and in git for review; never ambient).
2. CHECK-TIME CONSULT: eagerContentHashCheck, on a released-tag mismatch, consults the declarations BEFORE any refuse or fallback. EXACT provenance match required — box ledger hash == declared old_sha256 AND on-disk hash == declared new_sha256 → machinery re-stamp (UPDATE db.migration.content_hash, a code write via the migrate runner, never manual) + ONE loud line naming the declaration (version, old→new, reason, ticket). Anything undeclared or partially matching → the existing refuse, unchanged. Blanket re-hash-if-clean is REJECTED: it silently blesses every future retroactive edit and removes the immutability guard's teeth; the declaration keeps each bless explicit and auditable.
3. ORDERING vs STATBUS-156: the declaration consult runs FIRST (a declared restamp is more precise than a stale-cache full replay); 156's dev-only clean-file fallback stays as-is behind it. STATBUS-102's edge auto-recreate remains out of scope.
4. BACKFILL the first declaration: version 20260218215337, old cd82bc76…, new 71befa05… (full hashes from the dev journal / recompute), reason "8b5912a9a retroactive seed-drift fix", ticket STATBUS-156-adjacent history.
5. Idempotent + fleet-converging by construction: each slot re-stamps on its next NORMAL upgrade attempt (boot-migrate or pipeline migrate both route through the check); no manual DB writes anywhere; a box that never applied the old bytes matches nothing and is untouched.

ORACLE: (i) Go unit tests on the match logic (exact match → restamp; wrong old-hash → refuse; undeclared → refuse; declared-but-dirty-file → refuse); (ii) THE REAL ONE: the blocked dev-slot deploy re-dispatched goes green through the normal path — STATBUS-123's dev gate is the oracle, and its current red is the RED half already in hand; (iii) the loud restamp line appears exactly once per slot per conveyance in the journal.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A declared conveyance (exact old→new hash match, clean file) re-stamps the ledger through the NORMAL migrate path with one loud named line — no manual writes, no exit 21
- [ ] #2 Anything undeclared, partially matching, or dirty still hard-refuses exactly as today (immutability teeth intact) — unit-tested on all four branches
- [ ] #3 The 20260218215337 conveyance is backfilled and the dev-slot deploy goes green through the normal path (the STATBUS-123 gate oracle)
- [ ] #4 STATBUS-156's dev fallback ordering: declaration consult first, full-replay fallback second — verified in dev
<!-- AC:END -->
