---
id: STATBUS-079
title: >-
  stamp-gate-hardening: lock in the STATBUS-078 gate so a future edit can't
  silently re-open the dirty-stamp hole
status: In Progress
assignee: []
created_date: '2026-06-17 19:03'
updated_date: '2026-06-17 20:12'
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
WHAT: two small hardening additions that protect the STATBUS-078 stamp-guard against a FUTURE edit silently re-opening the "dirty stamp" hole.

1. FAIL-FAST CATCH-ALL: a `*)` default in BOTH dev.sh stamp-guard caller switches, so an unexpected guard return code fails LOUDLY instead of falling through silently — a fall-through would leave the withhold-flag unset → write a stamp from a dirty tree, the exact corruption STATBUS-078 exists to prevent.

2. WRITE-SITE REGRESSION TEST: a source-structure check asserting all 3 stamp-write sites (fast-test, db-docs, types) STAY gated on the withhold decision. The existing self-test only covers the guard's return code, not the caller write-gates — so a future ungating would go uncaught.

WHY: STATBUS-078 made landing a migration override-free (no FORCE=1 / no --no-verify). This keeps it that way as the code evolves.

STATUS: in progress; lands as its OWN commit, parallel to the rc.04 re-run; NOT cut-blocking (no hole today — the guard returns only 0/1/3).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SCOPE ADD (2026-06-17): also add a fail-fast `*)` catch-all to the two dev.sh stamp-guard caller switches (fast-test + generate-doc-db) so an UNEXPECTED guard rc fails loud (`echo "unexpected stamp-guard rc=$guard_rc" >&2; exit 1`) instead of silently falling through. Declined from COMMIT 1 (STATBUS-078) because the guard returns only 0/1/3 today (grep-confirmed no rc 2 / no other producer) — purely-theoretical-future hardening, not a current bug. Lands here with the write-site source-assert as one deliberate gate-hardening pass. Engineer offered it during COMMIT 1; foreman deferred to keep COMMIT 1 focused.

PRIORITY BUMPED to HIGH (2026-06-17) — the architect sharpened the catch-all's rationale during COMMIT 1 (STATBUS-078): it is NOT theoretical-benign. With the dead `2) exit 1` removed, the caller switches cover exactly the guard's 0/1/3 contract — but a FUTURE unhandled rc would fall through SILENTLY → fast-test's FAST_STAMP_WITHHELD stays unset → `:-0` → WRITES THE STAMP, possibly on a dirty tree = the exact silent-dirty-stamp corruption class STATBUS-078 exists to prevent. So the `*) ... exit 1` catch-all is a no-silent-corruption / fail-fast guard, not style. Foreman deferred it from COMMIT 1 (820e79624) to avoid a churn-amend of an announced commit, NOT because it's low-value. LAND PROMPTLY as the deliberate gate-hardening commit (catch-all in BOTH dev.sh caller switches: `*) echo "check_stamp_guard: unexpected rc $guard_rc" >&2; exit 1 ;;` + the write-site source-assert). NOT rc.04-cut-blocking (no current hole — guard returns only 0/1/3 today), but should land before/around the re-run wrap. Architect recommends; engineer ready.

DISPATCHED to engineer (2026-06-17 ~20:05) — clean checkpoint: STATBUS-077/078 fully pushed (78e770ac), the 32-scenario re-run firing (27715901866), master SQL-health confirmed (tester local fast-test 84/0, test 002 passing). 079 = catch-all in BOTH dev.sh caller rc-switches (`*) echo unexpected rc; exit 1`) + write-site source-assert (3 stamp-write sites gated on the withhold decision). Lands as its OWN commit, parallel to the re-run (touches dev.sh + a test; does NOT affect the re-run's pinned 78e770ac image). Loop: engineer implements → bash -n + go build/vet + tester runs test-stamp-guard + the new assert → architect byte-reviews → foreman commits + pushes. Non-cut-blocking.
<!-- SECTION:NOTES:END -->
