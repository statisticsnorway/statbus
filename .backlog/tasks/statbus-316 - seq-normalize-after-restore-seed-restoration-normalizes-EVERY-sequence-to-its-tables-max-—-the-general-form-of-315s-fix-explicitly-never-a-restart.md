---
id: STATBUS-316
title: >-
  seq-normalize-after-restore: seed restoration normalizes EVERY sequence to its
  table's max — the general form of 315's fix, explicitly never a restart
status: To Do
assignee: []
created_date: '2026-08-28 23:48'
labels:
  - tooling
  - testing
dependencies: []
priority: medium
type: enhancement
ordinal: 309000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a restored seed behaves identically to a freshly built one, for every sequence, including ones nobody has thought about yet. STATBUS-315 proved auth.user_id_seq diverges across seed artifacts (burned sequence values don't roll back, so the position depends on the path taken); the tonight-fix normalizes that ONE sequence in test/setup.sql. This ticket is the general solution.

THE RULED SHAPE (architect, 315 ruling — the option text's phrasing was rejected as dangerous): NOT "guarantee sequence restart" — a blanket restart collides with seed rows on every table that carries them, the same defect as the naive per-sequence fix generalized across the schema. The correct form: after restore, normalize EVERY sequence to its own table's max (the standard setval-from-max sweep over pg_sequences/pg_depend ownership). Determinism by derivation: the position comes from the DATA, discarding burn history, so artifacts converge regardless of how they were built.

WHERE: the seed-restore path (./sb db seed restore / dev.sh's restore step) — machinery, so it gets its own design and review, not a same-sitting fold-in.

REDUNDANCY CONTRACT (architect's explicit requirement): when this lands, the tactical setval line in test/setup.sql for auth.user_id_seq becomes redundant and must be REMOVED in the same commit — that line carries a comment pointing here; never two mechanisms doing one job.

WHAT IS ACHIEVED: sequence state stops being an artifact of construction path anywhere, and the 315 class cannot recur on a sequence nobody wrote a test about.
<!-- SECTION:DESCRIPTION:END -->
