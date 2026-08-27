---
id: STATBUS-292
title: >-
  doc-db-seed-staleness: doc/db regenerates from the SEED, so a post-seed
  migration amendment leaves generated docs silently stale
status: To Do
assignee: []
created_date: '2026-08-27 21:51'
labels:
  - testing
  - doc
  - tooling
dependencies: []
priority: low
type: bug
ordinal: 285000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during 267's landing (2026-08-27): generate-doc-db builds its documentation database from a clone of the test TEMPLATE, which comes from the SEED (dev.sh ~:2290-2300) — NOT from the dev database. So when a migration is amended and re-applied to the dev DB after the seed was built, the regenerated doc/db still dumps the PRE-amendment definitions, and `migrate down` has no --target seed (only up does), so the seed cannot be cheaply rolled back to absorb the amendment.

Why the freshness hook cannot catch it: both the migration file and the doc/db file legitimately changed in the same commit — the pairing looks satisfied while the doc content is one amendment behind. Tonight's instance was measured harmless (comment-only divergence; executable SQL identical 11/11 lines) and self-corrects at the next seed rebuild, but the mechanism admits a WORSE case: a substantive post-seed amendment would ship doc/db content that matches neither the file nor any database, and nothing would flag it.

Fix shapes to weigh (architect): (a) generate-doc-db detects seed-behind-HEAD (it knows the seed's migration version) and refuses or warns when on-disk migrations are newer than the seed's applied set INCLUDING content hashes, not just version numbers — content is the miss here; (b) generate-doc-db gains a mode that applies pending/amended migrations to its throwaway clone before dumping (self-contained, no shared-state rebuild); (c) documentation-only: the amend-a-migration runbook gains the step 'recreate-seed before generate-doc-db'. (b) is the shape that removes the trap rather than documenting it.

WHAT IS ACHIEVED: generated database documentation can never silently describe a version of a function that no longer exists anywhere.
<!-- SECTION:DESCRIPTION:END -->
