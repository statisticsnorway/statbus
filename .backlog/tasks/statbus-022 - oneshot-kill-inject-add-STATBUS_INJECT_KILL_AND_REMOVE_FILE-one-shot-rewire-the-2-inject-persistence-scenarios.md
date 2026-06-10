---
id: STATBUS-022
title: >-
  oneshot-kill-inject: add STATBUS_INJECT_KILL_AND_REMOVE_FILE (one-shot) +
  rewire the 2 inject-persistence scenarios
status: To Do
assignee: []
created_date: '2026-06-10 20:13'
labels:
  - install-recovery
  - harness
  - inject
dependencies: []
priority: medium
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BUCKET-A fix from the comprehensive run (27242482272). 3-postswap-mid-migration-kill + 3-postswap-between-migrations-kill fail because the kill-inject env (STATBUS_INJECT_AT) PERSISTS in the process tree, and the 017 fix made crash-recovery run INLINE (same process) — so the persistent inject RE-KILLS the recovery migrate (exit 137) → rolled_back, when the scenario expects completed. NOT a production regression (a real one-time kill lets the recovery migrate re-apply cleanly → completed); the test models an impossible repeated-kill. Architect classification: tmp/plans/architect-comprehensive-classification-27242482272.md.

DESIGN (agreed with the King): KillHere (cli/internal/inject/inject.go:364) currently fires EVERY time `os.Getenv(EnvActiveAt)==name`. Add a ONE-SHOT, file-armed variant controlled by a new env var:

  STATBUS_INJECT_KILL_AND_REMOVE_FILE=<path>

Semantics: at the inject site, if the file at <path> EXISTS → `os.Remove(path)` then `os.Exit(137)`; if ABSENT → no-op. The harness ARMS by creating the file; the inject CONSUMES it on fire = exactly one kill per arming. A filesystem MARKER (not a sync.Once / in-memory flag) is required because the kill re-execs the process (syscall.Exec) — in-memory one-shot state would be wiped; a file survives. Name is intent-first + honest (avoid THEN: KILL_THEN_REMOVE would be mechanically false since remove precedes the exit; AND is true regardless of order) and symmetric with the existing STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE.

WORK: (1) add the env var + the file-armed one-shot branch in KillHere; (2) extend Validate()'s truth table (cli/internal/inject/inject.go:318) for the new var (e.g. only meaningful for kill classes; reject for stall/error/external like the stall release-file rejects); (3) unit test in inject_test.go (fires once, removes the file, second hit no-ops); (4) rewire 3-postswap-mid-migration-kill + 3-postswap-between-migrations-kill to ARM via the new var instead of relying on the persistent inject. Result: models a ONE-TIME kill → recovery migrate succeeds → completed (matches production). The broken-migration-fails-every-time case is SEPARATE and already green (3-postswap-migration-deterministic-error, cell e).

inject.go is in the product binary but INERT in production (only fires when STATBUS_INJECT_AT is set, which only the harness does). Not blocking 017 ratification.
<!-- SECTION:DESCRIPTION:END -->
