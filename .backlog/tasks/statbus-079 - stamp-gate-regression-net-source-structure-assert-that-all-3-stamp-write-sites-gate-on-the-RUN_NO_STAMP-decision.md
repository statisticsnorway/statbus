---
id: STATBUS-079
title: >-
  stamp-gate-regression-net: source-structure assert that all 3 stamp-write
  sites gate on the RUN_NO_STAMP decision
status: To Do
assignee: []
created_date: '2026-06-17 19:03'
updated_date: '2026-06-17 19:09'
labels:
  - dx
  - safety-machinery
  - testing
  - follow-up
dependencies:
  - STATBUS-078
references:
  - 'dev.sh:812'
  - 'dev.sh:1894'
  - 'cli/cmd/types.go:108-115'
priority: medium
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from STATBUS-078 (architect observation C). Test 5 (dev.sh test-stamp-guard) is GUARD-level: it asserts the guard returns rc=3 on dirty + the guard itself never writes a stamp. It does NOT assert the three CALLER write-gates (the invariant "all 3 stamp-write sites gate on the decision together"). Today that invariant holds and is verified by byte-review (foreman + architect), but a FUTURE edit could ungate one write site and no test would catch it — re-opening the dirty-stamp hole the gate-pedagogy change closed.

ADD a source-structure regression net (cheap, DB-free): assert each of the 3 stamp-write sites is guarded by its withhold decision —
- dev.sh:812 fast-test write must be inside the `FAST_STAMP_WITHHELD` gate
- dev.sh:1894 db-docs write must be inside the `DOCDB_STAMP_WITHHELD` gate
- cli/cmd/types.go:~109 types write must be gated on `stampDecision != stampGuardRunNoStamp`
Either a grep/structure self-test (mirror the dev.sh test-stamp-guard style) or a Go test asserting the source contains the gate around each write. Non-blocking; the invariant holds now (COMMIT 1). Owner: engineer; architect review.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SCOPE ADD (2026-06-17): also add a fail-fast `*)` catch-all to the two dev.sh stamp-guard caller switches (fast-test + generate-doc-db) so an UNEXPECTED guard rc fails loud (`echo "unexpected stamp-guard rc=$guard_rc" >&2; exit 1`) instead of silently falling through. Declined from COMMIT 1 (STATBUS-078) because the guard returns only 0/1/3 today (grep-confirmed no rc 2 / no other producer) — purely-theoretical-future hardening, not a current bug. Lands here with the write-site source-assert as one deliberate gate-hardening pass. Engineer offered it during COMMIT 1; foreman deferred to keep COMMIT 1 focused.
<!-- SECTION:NOTES:END -->
