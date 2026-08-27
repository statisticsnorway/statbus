---
id: STATBUS-270
title: >-
  crystal-spec-broken: cli/spec fails to compile on master — the worker has no
  runnable test suite at all
status: To Do
assignee: []
created_date: '2026-08-27 13:05'
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
