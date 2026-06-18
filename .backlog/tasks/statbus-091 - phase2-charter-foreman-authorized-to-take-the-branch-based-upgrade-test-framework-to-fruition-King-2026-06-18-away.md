---
id: STATBUS-091
title: >-
  phase2-charter: foreman authorized to take the branch-based upgrade-test
  framework to fruition (King, 2026-06-18, away)
status: In Progress
assignee: []
created_date: '2026-06-18 14:55'
labels:
  - upgrade
  - phase-2
  - authority
  - framework
dependencies: []
priority: high
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AUTHORITY (King, 2026-06-18, explicitly granted before going away):
The foreman is BLESSED + CHARGED to drive the following to fruition autonomously while the King is away:
1. Fix ALL reported issues (STATBUS-087 history label, -088 log wording, -089 maintenance/config-drift + the upgrade-should-regen-config product gap, -090 status-lag race; the harness infra-transport flakiness).
2. Land the architecture improvements already designed + ratified (STATBUS-086 upgrade CLI verbs, -034 branch-channel, -072 amend-migration-conveyance).
3. IMPLEMENT THE WHOLE branch-based upgrade-test framework (STATBUS-071) + the failure-mode matrix on real upgrades (STATBUS-044).

GRANTED POWERS (verbatim intent): commit locally, push to master, create + push the test branches (test/base, test/<defect>, test/<defect>-fixed, …) and all required effects (images, CI workflows, channels). Take it all the way to fruition. "You've been blessed by me to do those things."

RATIONALE (King): it follows logically — we CANNOT test the upgrade failure/fix scenarios without this framework. The fabricated public.upgrade-row + injected-kill workarounds are being retired; real branch arcs (install A → upgrade to a defective B → fix via C, via the real web-approve→NOTIFY→service path) are the only faithful test.

QUALITY BAR the foreman holds (self-imposed, unchanged): review every diff before commit; master always builds + green; ship bit-by-bit (no heap); the run is the only oracle (commit→push→CI image→run→observe→iterate); commit via `git commit -F`; no --no-verify/FORCE=1; no #<digit> in commit messages; no manual DB writes on any environment (fixes ship via code + idempotent install); SSH reads OK, SSH writes forbidden.

BUILD ORDER (dependency-aware):
- WAVE 1 (parallel, disjoint files): engineer → STATBUS-086 (CLI verbs, the test-driver foundation; owns cli/cmd/upgrade.go + service.go + commit.go). mechanic → STATBUS-087 (frontend page.tsx count; King leaned "N applied · M superseded"). architect → implementable STATBUS-071 build spec + STATBUS-089 config-regen-on-upgrade design.
- WAVE 2 (product changes on the upgrade path, sequenced through the engineer to avoid service.go conflicts): STATBUS-072 (amend+re-stamp), STATBUS-034 (branch-channel), STATBUS-089 (upgrade regenerates config), STATBUS-090 (NOTIFY-after-completed + reconnect-refetch), STATBUS-088 (operator-facing wording).
- WAVE 3 (the goal): STATBUS-071 arc harness — test branches + upgrade-arc-harness.yaml + register+schedule driver + inject-on-real-upgrade for precise kills + clean-slate-after-rollback fingerprint; then STATBUS-044 the failure-mode matrix.

This task is the durable record of the authority + the master tracker for the Phase-2 drive. Supersedes the Phase-2 half of STATBUS-075 (which tracked the install RC, now cut as v2026.06.0-rc.04).
<!-- SECTION:DESCRIPTION:END -->
