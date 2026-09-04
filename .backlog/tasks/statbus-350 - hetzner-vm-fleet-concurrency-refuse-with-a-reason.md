---
id: STATBUS-350
title: >-
  hetzner-vm-fleet concurrency: a third entrant is cancelled silently; make it refuse with a reason
status: To Do
assignee: []
created_date: '2026-09-04 06:40'
updated_date: '2026-09-04 06:40'
labels:
  - release
  - ci
  - fail-fast
dependencies: []
priority: high
type: bug
ordinal: 343000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed 2026-09-04 on v2026.09.0-rc.14: the foreman hand-dispatched upgrade-arc-harness.yaml at the tag (run 33835503755) while the tag-fired orchestrator was dispatching test-install and test-upgrade. All three share `concurrency: group: hetzner-vm-fleet` (one running + one pending). test-install 33835566015 became the third entrant and was CANCELLED with zero jobs and no line saying why; test-upgrade 33835572467 sat pending behind the arcs past the orchestrator's 2700s poll budget, so orchestrator 33835497127 failed on timeout with no product red anywhere. Recovery cost: a manual `gh run rerun` of the orchestrator after the arcs finished, about two hours of wall clock, and a confused morning.

The King's rule is actionable fail-fast. A silent cancellation is the opposite.

Fix shape (either; the foreman prefers 1 first):
1. Each fleet workflow's first job probes `gh run list` for a live run in the group at a DIFFERENT run id on the same tag or sha and FAILS with: "refused: run <id> (<workflow>) owns hetzner-vm-fleet for <tag>; wait for it or cancel it deliberately". The message is the fix.
2. Per-tag concurrency group plus the orchestrator as the only dispatcher on a tag; hand dispatch documented as "only when no orchestrator is live for this tag".

Also document in test/install-recovery/README.md: never hand-dispatch into the fleet group while an orchestrator is live on the same tag.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
<!-- COMMENTS:END -->
