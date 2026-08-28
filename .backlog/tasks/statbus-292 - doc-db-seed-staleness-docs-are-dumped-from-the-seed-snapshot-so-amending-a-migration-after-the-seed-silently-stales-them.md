---
id: STATBUS-292
title: >-
  doc-db-seed-staleness: docs are dumped from the seed snapshot, so amending a
  migration after the seed silently stales them
status: To Do
assignee: []
created_date: '2026-08-27 21:51'
updated_date: '2026-08-28 07:10'
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
NORTH STAR: doc/db — the offline markdown dump of every database function, table, and view — must always describe the migrations as they exist on disk. Today there is one sequence of ordinary steps after which it silently describes code that no longer exists anywhere.

THE ISSUE. generate-doc-db does not read the dev database. It builds its documentation database by cloning the test template, which is built from the SEED — a snapshot taken when the seed was last rebuilt (dev.sh ~:2290-2300). So the sequence: (1) seed is built, (2) a migration file is amended, (3) the amended migration is applied to the dev DB, (4) generate-doc-db runs — produces docs dumped from the PRE-amendment definitions. Nothing warns. And the seed cannot be cheaply rolled back to absorb the amendment: migrate down has no --target seed (only up has --target).

WHY THE EXISTING GUARD MISSES IT. The commit gate checks that migration changes and doc/db changes arrive PAIRED. In this sequence both files legitimately changed in the same commit — the pairing is satisfied while the doc content is one amendment behind. The guard checks that both moved, not that they agree.

OBSERVED INSTANCE (267's landing, 2026-08-27): measured harmless — the divergence was comment-only, executable SQL identical 11/11 lines — and it self-corrects at the next seed rebuild. But the mechanism admits the worse case: a substantive post-seed amendment would ship doc/db content matching neither the file on disk nor any database, and nothing would flag it.

FIX SHAPES, for the architect to rule:
(a) DETECT: generate-doc-db knows the seed's migration version; refuse or warn when on-disk migrations are newer than the seed's applied set — compared by CONTENT HASH, not just version number, since content divergence at the same version is exactly the miss here.
(b) ABSORB: generate-doc-db applies pending/amended migrations to its own throwaway clone before dumping. Self-contained, no shared-state rebuild, and the trap is removed rather than reported.
(c) DOCUMENT: the amend-a-migration runbook gains the step "recreate-seed before generate-doc-db".
Recommendation: (b) — it removes the trap; (a) documents it loudly; (c) documents it quietly.

WHAT IS ACHIEVED: generated database documentation can never silently describe a version of a function that no longer exists anywhere.
<!-- SECTION:DESCRIPTION:END -->
