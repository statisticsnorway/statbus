---
id: STATBUS-079
title: >-
  stamp-gate-regression-net: source-structure assert that all 3 stamp-write
  sites gate on the RUN_NO_STAMP decision
status: In Progress
assignee: []
created_date: '2026-06-17 19:03'
updated_date: '2026-06-17 20:05'
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
priority: high
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

PRIORITY BUMPED to HIGH (2026-06-17) — the architect sharpened the catch-all's rationale during COMMIT 1 (STATBUS-078): it is NOT theoretical-benign. With the dead `2) exit 1` removed, the caller switches cover exactly the guard's 0/1/3 contract — but a FUTURE unhandled rc would fall through SILENTLY → fast-test's FAST_STAMP_WITHHELD stays unset → `:-0` → WRITES THE STAMP, possibly on a dirty tree = the exact silent-dirty-stamp corruption class STATBUS-078 exists to prevent. So the `*) ... exit 1` catch-all is a no-silent-corruption / fail-fast guard, not style. Foreman deferred it from COMMIT 1 (820e79624) to avoid a churn-amend of an announced commit, NOT because it's low-value. LAND PROMPTLY as the deliberate gate-hardening commit (catch-all in BOTH dev.sh caller switches: `*) echo "check_stamp_guard: unexpected rc $guard_rc" >&2; exit 1 ;;` + the write-site source-assert). NOT rc.04-cut-blocking (no current hole — guard returns only 0/1/3 today), but should land before/around the re-run wrap. Architect recommends; engineer ready.

DISPATCHED to engineer (2026-06-17 ~20:05) — clean checkpoint: STATBUS-077/078 fully pushed (78e770ac), the 32-scenario re-run firing (27715901866), master SQL-health confirmed (tester local fast-test 84/0, test 002 passing). 079 = catch-all in BOTH dev.sh caller rc-switches (`*) echo unexpected rc; exit 1`) + write-site source-assert (3 stamp-write sites gated on the withhold decision). Lands as its OWN commit, parallel to the re-run (touches dev.sh + a test; does NOT affect the re-run's pinned 78e770ac image). Loop: engineer implements → bash -n + go build/vet + tester runs test-stamp-guard + the new assert → architect byte-reviews → foreman commits + pushes. Non-cut-blocking.
<!-- SECTION:NOTES:END -->
