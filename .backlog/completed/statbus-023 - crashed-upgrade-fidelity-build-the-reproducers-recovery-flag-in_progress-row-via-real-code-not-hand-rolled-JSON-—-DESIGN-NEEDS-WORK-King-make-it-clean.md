---
id: STATBUS-023
title: >-
  crashed-upgrade-fidelity: build the reproducers' recovery flag + in_progress
  row via real code, not hand-rolled JSON — DESIGN NEEDS WORK (King: make it
  clean)
status: Done
assignee: []
created_date: '2026-06-10 20:13'
updated_date: '2026-07-06 15:58'
labels:
  - install-recovery
  - harness
  - test-fidelity
  - needs-design
dependencies: []
priority: medium
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FIDELITY GAP raised by the King (2026-06-10 design discussion). The STATBUS-017 reproducers (3-postswap-migrate-killed-after-commit, 3-postswap-migration-deterministic-error) fabricate the crashed-upgrade PRECONDITION by HAND: _fabricate_crash_flag hand-writes tmp/upgrade-in-progress.json as raw JSON, and fabricate_scheduled_upgrade_row hand-writes the public.upgrade in_progress row via raw SQL INSERT. Neither goes through the REAL product writer (acquireFlock → json.MarshalIndent(UpgradeFlag), cli/internal/upgrade/service.go:285; the UpgradeFlag struct is service.go:231).

WHY IT MATTERS: the hand-rolled JSON is faithful only by manual maintenance, with NO compiler check. Proof it drifts: the struct's own field comment (service.go:240) is already STALE — it documents only FlagPhasePreSwap/PostSwap and never mentions FlagPhaseResuming (service.go:204), the exact phase the reproducer hand-writes. A future edit could silently encode a flag the real code never writes, and the test would pass against a fossil. (The recovery PATH under test IS real — runCrashRecovery → boot-migrate-up → 017 fall-through → RecoverFromFlag → resumePostSwap → rollback → restore; this is purely about precondition fidelity.)

WHY FABRICATION IS NEEDED AT ALL (not a full real upgrade): (1) the product deliberately won't `./sb upgrade schedule` an untagged HEAD — only released CalVer tags — so testing an upgrade to an unreleased commit REQUIRES fabricating the scheduled/in-progress state; (2) the after-commit cell-c state (committed-but-unrecorded migration) is a ~ms window that a real SIGKILL can only catch flakily. So deterministic fabrication is the right reliability choice; the goal is to make the fabricated artifacts BYTE-FAITHFUL to what the real code writes.

GOAL: produce the flag (and ideally the in_progress row) through the REAL serialization/writer code so it's byte-identical + drift-as-COMPILE-ERROR, plus a round-trip contract test (real ReadFlagFile parses the fabricated flag).

⚠ KING DIRECTIVE — DESIGN NEEDS MORE EFFORT: the foreman's first proposal (a hidden `./sb upgrade __write-flag` subcommand / a WriteFlagForTest backdoor in the product binary) was NOT clean — a production-CLI backdoor purely for tests is a smell. Design a CLEANER mechanism. CONSTRAINTS to design around: (a) NO Go toolchain on the test VMs (so anything Go-based must run on the CI runner and scp the artifact, like the seed); (b) avoid polluting the production binary/CLI with test-only entrypoints; (c) the harness is bash; (d) want compile-checked fidelity to the real UpgradeFlag struct + the real MarshalIndent. Candidate directions (NOT decided — architect to design): a test-only fixture generator under test/ that imports cli/internal/upgrade and emits the flag via the real Marshal (runs on the CI runner, scp to VM); OR a Go contract test that asserts the hand-rolled JSON exactly equals acquireFlock's output for the same struct (keeps bash simple, guards drift); OR another approach. ARCHITECT owns the design.

Not blocking STATBUS-017 ratification.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSE — SUPERSEDED. It asked to make hand-rolled fabrication (crash flag JSON + upgrade row SQL) byte-faithful to the real writers. STATBUS-071's King-ratified direction retires that fabrication entirely (AC#3: real register+schedule replaces the fabricated row; AC#4: fabricate_scheduled_upgrade_row deleted at zero callers). The specific reproducers 023 targeted were already deleted in the 071 reshape. If any fabrication survives 071's sweep, its fidelity is judged inside that sweep.
<!-- SECTION:FINAL_SUMMARY:END -->
