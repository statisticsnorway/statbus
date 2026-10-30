---
id: STATBUS-270
title: >-
  crystal-spec-broken: cli/spec fails to compile on master — the worker has no
  runnable test suite at all
status: Done
assignee: []
created_date: '2026-08-27 13:05'
updated_date: '2026-08-28 21:39'
labels:
  - worker
  - testing
dependencies: []
priority: medium
type: bug
ordinal: 263000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during STATBUS-264: cli/spec/statbus_spec.cr fails to compile on master — `undefined constant StatBus` (the module is `Statbus`) — so `crystal spec` does not run and has not for some time. The Crystal worker (cli/src/worker.cr) therefore has NO runnable automated tests; the only oracle for worker changes is the type-checker via an entrypoint build (and note: `crystal build --no-codegen` on the library file alone verifies nothing — Crystal only type-checks reachable method bodies; the engineer proved this by mutation).

Fix the spec compilation, then decide what minimal worker coverage is worth having — 264's retry loop and the startup crash recovery are the immediate candidates (their behaviour under a real refusal is currently unproven until a live run exercises it).

WHAT IS ACHIEVED: worker changes have a runnable automated oracle again, and the no-flaky-tests discipline extends to the Crystal side.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLOSED at 87385e81a: one line — the spec referenced StatBus where the module is Statbus, so the suite had not compiled since the rename. 20 examples now compile, run, and pass (transcript on the tester's report). No additional rot found. The substantive 264/265 coverage expansion (retry loop + startup crash recovery bodies) remains a deliberate follow-up, noted here so it is not read as delivered — what this fix buys is that a broken worker test CAN fail again.
<!-- SECTION:NOTES:END -->
