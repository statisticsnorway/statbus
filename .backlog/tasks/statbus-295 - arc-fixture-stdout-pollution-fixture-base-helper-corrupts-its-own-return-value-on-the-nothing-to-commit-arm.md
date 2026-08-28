---
id: STATBUS-295
title: >-
  arc-fixture-stdout-pollution: fixture-base helper corrupts its own return
  value on the nothing-to-commit arm
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-28 03:58'
updated_date: '2026-08-28 04:04'
labels:
  - install-recovery
  - ci
dependencies: []
priority: high
type: bug
ordinal: 288000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rc.13's arc fleet (harness run 33140187021, orchestrator 33136561614 leg 5) never launched: fixture construction died at exit 128 before a single VM was provisioned.

MECHANISM: _ut_fixture_base (test/install-recovery/lib/upgrade-target.sh:443) returns its result — one commit SHA — via stdout, captured by command substitution. At :489 it runs `git commit -S -q ... || { echo "nothing to commit ..." >&2; }`. git commit's -q silences the summary only on SUCCESS; on nothing-to-commit it prints the status block ("HEAD detached at v2026.08.0-rc.13 / nothing to commit, working tree clean") to STDOUT and exits 1. The || arm handles the exit code, but the chatter has already leaked into the function's stdout return. Downstream, construct_upgrade_target does `git checkout -b $B_BRANCH "$polluted_sha"` → fatal, exit 128, entire fleet skipped.

WHY ONLY AT RC.13: this arm had NEVER executed. It fires only when the base commit's .github/workflows/ already exactly equals origin/master's — true for the first time at rc.13, whose tag commit d663b2010 sat at master's tip with no workflow-touching commits after it. Every earlier arc run took the commit-succeeds arm.

SECOND DEFECT, same line: a REAL commit failure (signing, hooks, disk full) also lands in the || and is reported as "nothing to commit" — a genuine failure masquerading as the benign branch.

FIX SHAPE: decide-then-act — probe emptiness with `git diff --cached --quiet` (index vs HEAD is exactly the question); if empty, log the benign line to stderr and use the base SHA; else `git commit -S -q -m ... >/dev/null` where ANY failure is now a loud stderr + return 1. Plus a scoped sweep: every stdout-returning function in the harness libs checked for unredirected git/tool chatter on any arm.

RELAUNCH PATH, no rc.14 needed: the arc-harness fixture job's checkout has no ref: override, so it checks out the RUN's github.sha — the dispatched ref's tip (master), not the RC tag. Land the fix on master, then re-run the orchestrator's failed leg 5 (gh run rerun 33136561614 --failed); the re-dispatched harness picks up the fixed lib.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-28 04:00
---
FIX LANDED at 84c99c7ed (single file, +37/−7): decide-then-act — git diff --cached --quiet separates the benign empty-index case (stderr line, base SHA used) from a real commit failure (now loud and fatal; previously a signing/hook/disk failure was reported as 'nothing to commit' and execution CONTINUED on an uncommitted tree — the more dangerous of the two defects). Engineer's sweep, with the honest discriminator being 'does the caller capture the function with $( )' (17 such functions in the libs): 7 unredirected stdout writers found — 2 by design (VM_EXEC and snapshot_demo_data_counts, where the ssh output IS the value) and 5 side-effecting git calls in _ut_fixture_base (fetch/checkout --detach/read-tree/checkout -- path/add -A), all now structurally redirected — 'probably quiet given -q' is exactly the assumption that cost the chain. Demo reproduced the exact arm: old form captures a 3-line polluted value and dies fatal at checkout -b; new form captures a clean 40-hex SHA. bash -n clean, shellcheck delta zero. RELAUNCHED: orchestrator 33136561614's failed leg 5 rerun dispatched — the fixture job checks out master's tip, which now carries the fix. Engineer's closing observation, worth keeping: same disease, third organ tonight — a check whose pipe corrupted its verdict (227), a function whose chatter corrupted its value (295), a comparison whose undefined answer corrupted a decision (293); all three shipped for months because each LOOKED like it was reporting.
---

author: foreman
created: 2026-08-28 04:04
---
CORRECTION — my relaunch-path claim in the description and comment #1 was WRONG, and the rerun proved it: the orchestrator dispatches leg 5 with the workflow ref pinned to the TAG (rerun harness 33140577188: event=workflow_dispatch, headBranch=v2026.08.0-rc.13, headSha=d663b2010), so the fixture job checked out the tag's OLD lib and died on the identical bytes. My 'checks out master's tip' inference read the checkout step (no ref: override → github.sha) correctly but got the dispatch ref wrong — for workflow_dispatch, github.sha IS the dispatched ref, and the orchestrator pins it to the tag deliberately (the arc must test the candidate's own tree). Verify-before-writing miss on my part; the run was the oracle as always. CONSEQUENCE: the fix can only reach the fleet inside a candidate → rc.14 cuts from master tip once CI covers 84c99c7ed. A hand-dispatch of the harness at ref master with base_sha=d663b2010 would exercise the fixed lib against rc.13's tree, but the orchestrator's own record would stay red and release-fleet-orchestrator.yaml:106 already documents hand-dispatch-bypassing-the-orchestrator as the anti-pattern it is — not taken.
---
<!-- COMMENTS:END -->
