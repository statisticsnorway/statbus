---
id: STATBUS-295
title: >-
  arc-fixture-stdout-pollution: fixture-base helper corrupts its own return
  value on the nothing-to-commit arm
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-28 03:58'
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
