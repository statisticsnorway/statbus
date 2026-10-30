---
id: STATBUS-022
title: >-
  oneshot-kill-inject: add STATBUS_INJECT_KILL_AND_REMOVE_FILE (one-shot) +
  rewire the 2 inject-persistence scenarios
status: Done
assignee: []
created_date: '2026-06-10 20:13'
updated_date: '2026-06-11 07:49'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IMPLEMENTED (engineer, 2026-06-10, working tree — foreman sole committer). Parts 1-3 (inject primitive) DONE+tested; part 4 (scenario rewire) DONE, bash -n clean. Files: cli/internal/inject/inject.go (EnvKillAndRemoveFile const + one-shot file-armed KillHere + Validate truth-table extension), cli/internal/inject/inject_test.go (TestKillHere_OneShotArmedFile via subprocess re-exec; TestValidate_AllRows +6 kill-file rows), test/install-recovery/scenarios/3-postswap-mid-migration-kill.sh + 3-postswap-between-migrations-kill.sh. make -C cli build clean; go test ./internal/inject/ PASS.

STRUCTURAL NOTE part 4: code-trace showed the 017 inline recovery + syscall.Exec(os.Args, os.Environ()) re-exec (service.go:3624) means the FIRST install does the WHOLE recovery inline. With the one-shot the first install KILLS ONCE then SELF-HEALS to completed inline — it does NOT leave the pre-017 RED in_progress state. Both scenarios collapsed to a SINGLE self-healing install asserting: arm-file consumed (proves the one kill fired) + row=completed + db.migration max_version advanced past baseline + data intact. The RED-assert + recovery second-install were removed (pre-017 assumption). Headers updated to match.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Committed f27d5fef9 on master. Added one-shot file-armed kill STATBUS_INJECT_KILL_AND_REMOVE_FILE (atomic os.Remove-gates-os.Exit, no stat, no re-kill on a failed remove) to cli/internal/inject/inject.go + inject_test.go subprocess one-shot test; rewired 3-postswap-mid-migration-kill + 3-postswap-between-migrations-kill to a SINGLE self-healing install (arm consumed = exactly one kill; 017 inline recovery re-runs the migrate un-killed → completed) with arm-consumed + FIRST_EXIT==0 + completed + migration-advanced asserts; removed the pre-017 RED-then-second-install. Architect-reviewed PASS (atomic fix + faithfulness code-trace). PROVEN GREEN on real VMs: run 27306718138 — BOTH mid-migration-kill and between-migrations-kill PASS.
<!-- SECTION:FINAL_SUMMARY:END -->
