---
id: STATBUS-153
title: >-
  arc-fixture-shallow-fetch: fixture construction cannot read a base SHA once
  master moves — fetch the base explicitly
status: Done
assignee: []
created_date: '2026-07-09 00:15'
updated_date: '2026-07-13 09:59'
labels:
  - install-recovery
  - ci
  - tooling
dependencies: []
references:
  - test/install-recovery/
  - .github/workflows/
priority: medium
ordinal: 154000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: an arc dispatch targeting any reachable commit succeeds regardless of how far master has advanced since the dispatch was created.
> STAGE: harness robustness. FOUND: wave-5 dispatch 28984225540 (2026-07-09 00:02) — cost one full dispatch cycle.
> COMPLEXITY: mechanic-simple.

OBSERVED: the "Construct branch fixtures + dispatch image builds" job failed with `fatal: unable to read tree (e1d57575f...)` at its first git command on the base SHA. Timeline: dispatch created at 00:02 with base_sha=e1d57575f (then master tip); two commits landed on master (ad080611b 00:12, b4df4bff2 00:13) before the job's checkout ran; the job's shallow checkout materialized only the NEW tip's history, and the requested base SHA's tree was absent from the object store. The run died before any fixture branch, image, or VM was created (clean skip of all downstream jobs).

FIX DIRECTION: the fixture-construction job must guarantee the base SHA's objects exist before using them — either `fetch-depth: 0` on its checkout (cost: full-history clone per dispatch) or, better, an explicit `git fetch origin <base_sha>` (servers allow SHA fetch for advertised/reachable objects; master-reachable SHAs qualify) immediately before first use, with a loud, named error if the SHA is genuinely unreachable (deleted branch / GC'd object) rather than the bare `unable to read tree`.

ACCEPTANCE: a dispatch whose base SHA is N commits behind master's tip at job-start time constructs fixtures successfully; a genuinely unreachable SHA fails with an actionable message naming the SHA and the probable cause.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fixture construction explicitly fetches the base SHA (or full history) before first use — a moved master tip can no longer starve it
- [x] #2 A genuinely unreachable base SHA fails with a loud, named error (SHA + probable cause), not a bare git internals message
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Arc fixture construction died once ('fatal: unable to read tree', wave-5 dispatch 28984225540) when master advanced between dispatch and job start, leaving the requested base SHA outside the checkout's history — fetch-depth:0 was present the whole time and demonstrably insufficient (GitHub resolves the checkout ref at job-start). Fixed (b08456f50): an explicit `git fetch origin <base_sha>` before first use, with a genuinely unreachable SHA failing immediately as a named ::error (SHA + probable causes + git's own message) instead of a bare git-internals line later. Both paths sanity-probed live against origin before writing (ancestor SHA fetches clean; fabricated SHA yields the distinguishable 'not our ref'). The next arc-harness run exercises it organically.
<!-- SECTION:FINAL_SUMMARY:END -->
