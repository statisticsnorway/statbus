---
id: STATBUS-238
title: >-
  arc-fixture-hybrid-tree: fixture branches run master's CI definitions against
  the RC's scripts — loud-failure risk on old RCs, accepted without a guard
status: To Do
assignee: []
created_date: '2026-08-18 15:59'
labels:
  - ci
  - install-recovery
dependencies:
  - STATBUS-236
priority: low
type: chore
ordinal: 238000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
This ticket records an accepted risk, ruled by the architect on STATBUS-236 — it needs no build now. It exists so the failure, when it eventually appears, is recognized in minutes instead of triaged from scratch.

THE SITUATION: STATBUS-236's remedy aligns the fixture branches' .github/workflows/ with the default branch (required — the harness token cannot push divergent workflow trees). That makes every fixture branch a HYBRID: `gh workflow run --ref <fixture-branch>` executes the workflow file FROM that ref, so the fixture image build runs MASTER's CI definitions against the RC's scripts and tree.

REACHABILITY: it bites only for an RC old enough that master's CI expects files the RC's tree lacks (example of the class: master's images.yaml hard-fails without ops/release/ci-exempt-paths.txt at :133-138 — rc.04 has it, so no current RC is exposed). Today this is no RC we would ever re-run.

WHY NO GUARD (architect's ruling): the failure mode is a LOUD CI failure — a file master's CI expects is simply absent — never a silent wrong verdict. A guard would have to enumerate every file master's CI might read from an arbitrary older tree: unbounded, brittle, and it would rot faster than the thing it guards.

WHAT TO DO IF IT FIRES: a fixture image build failing with a missing-file error on an old RC is THIS, not an infrastructure fault. The remedy at that point is judged fresh — likely cutting a newer RC rather than teaching master's CI about old trees.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Closes when either the hybrid design is replaced (making this moot) or the documented failure fires once and this record proves sufficient to triage it quickly
<!-- AC:END -->
