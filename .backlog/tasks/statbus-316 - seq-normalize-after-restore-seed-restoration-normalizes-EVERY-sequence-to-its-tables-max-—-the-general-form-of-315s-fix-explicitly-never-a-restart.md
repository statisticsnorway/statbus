---
id: STATBUS-316
title: >-
  seq-normalize-after-restore: seed restoration normalizes EVERY sequence to its
  table's max — the general form of 315's fix, explicitly never a restart
status: Done
assignee:
  - mechanic
created_date: '2026-08-28 23:48'
updated_date: '2026-08-29 12:58'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Architect design (2026-08-29), complete — build may proceed after one checkpoint.** (1) SITE: the Go side — dev.sh already delegates (dev.sh:1935 → ./sb db seed restore). Go has several restore entries (runPgRestoreAtomic db.go:50, restoreSeedDump seed_build.go:194, runSeedRestore install.go:2020, restoreLocal db.go:531, restoreVerifyDB seed_verify.go:473); BUILDER CHECKPOINT before any edit: confirm every restore path reaches one primitive and REPORT — if they converge, normalize there; if not, MAKE them converge, never add the call at five sites. (2) ENUMERATION: pg_depend with deptype IN ('a','i') — 'a' alone silently skips every GENERATED…AS IDENTITY sequence; not pg_get_serial_sequence (wrong direction). (3) UNOWNED sequences: skip with reason AND pin the expected unowned set in a test (expect worker_task_priority_seq); a new unowned sequence must fail the test, not join the exceptions silently. (4) SETVAL FORM: setval(seq, COALESCE(max(col),1), max(col) IS NOT NULL) — bare max errors on empty tables, the COMMON case in a fresh seed. (5) PROOF, three properties: correctness (every owned seq = table max, or positioned to yield 1); DETERMINISM (restore the same artifact twice from different burn states → identical final positions — the actual 315 goal, proven directly); BIDIRECTIONALITY (ahead→pulled back = the defect; behind→pushed forward = duplicate-key safety; a naive only-lower implementation leaves the collision hazard). (6) Retire 315's tactical setup.sql setval IN THIS TICKET, not a follow-up.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at abd42b172, complete per the architect's design with his option-(b) ack. One PL/pgSQL procedure (public.normalize_all_sequences, migration 20260829114700) is the single source shared by every consumer — the Go restore paths and test/setup.sql CALL the same bytes, zero duplication. pg_depend with BOTH deptypes ('a'+'i'); setval(COALESCE(max,1), is_called=max-is-not-null) so empty tables — the fresh-seed common case — yield 1; bidirectional and idempotent by construction; unowned sequences reported by name and pinned as a set by test 127 (graphql.seq_schema_version, import_job_priority_seq, power_group_ident_seq, worker_task_priority_seq). All four restore paths call it at genuine completion points — restoreVerifyDB included, after confirming its digests are blind to sequence state by construction (pg_dump --schema-only, row content, migration ledger — none observe sequence positions), so normalization cannot mask drift detection. Derived guard (291 machinery's third reuse, minimum-count floor) makes a forgotten fifth path fail on the day it is written. 315's tactical setup.sql setval retired in this unit per the redundancy contract; the setup.sql CALL is message-quieted so the unowned-set pin lives in 127 alone, not in 72 accidental .out pins. Proof: correctness, bidirectionality (503→3 pulled back, 1→3 pushed forward), determinism (both burn paths converge to 3), settled no-op — all green; full fast suite to completion with zero diffs outside 127. The suite run also doubled as the kill-forensics experiment: launched detached, it survived where four session-parented runs died, confirming the session-group kill mechanism (recorded in team memory: long runs launch detached from now on).
<!-- SECTION:FINAL_SUMMARY:END -->
