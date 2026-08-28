---
id: STATBUS-296
title: >-
  arc-diagnostics-fail-fast: the failure-diagnostics step destroys the evidence
  it exists to capture when the db is down
status: To Do
assignee: []
created_date: '2026-08-28 07:59'
labels:
  - install-recovery
  - ci
dependencies: []
priority: medium
type: bug
ordinal: 289000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: when an arc scenario fails, the harness must capture the evidence that explains the failure. Today, the diagnostics-collection step destroys exactly that evidence in exactly the case that most needs it.

THE ISSUE. The arc harness's failure-diagnostics step ("target progress log + daemon journal + flag + row") runs its captures as a sequence of commands under fail-fast shell settings. When the database is the thing that is down, the FIRST command ("service db is not running" → exit 1) aborts the whole step before it reaches the daemon-journal fetch — the one artifact that would show whether the upgrade service panicked, and when. Observed twice on the same scenario (cross-version-rename-handoff, rc.11 run 33115731212 and rc.14 run 33145356673): both times the 30-minute-silence window's journal was never captured, and both triages had to argue from timeline fit instead of a stack trace.

This is the what-must-survive-a-failure class: evidence collection cannot live inside fail-fast semantics, because the failures it exists to document are precisely the states that make its own commands fail.

FIX SHAPE: every capture in the diagnostics step becomes individually failure-tolerant (|| echo "capture X unavailable: ..." per command, the same pattern _dump_bootstrap_failure_diagnostics already uses deliberately after STATBUS-227's forensics work) — a failed capture is itself a datum, reported in place, never a reason to skip the remaining captures. The daemon journal fetch moves BEFORE any capture that depends on services being up, since it depends only on SSH.

WHAT IS ACHIEVED: a scenario failure always yields its journal, and no triage has to argue from silence again.
<!-- SECTION:DESCRIPTION:END -->
