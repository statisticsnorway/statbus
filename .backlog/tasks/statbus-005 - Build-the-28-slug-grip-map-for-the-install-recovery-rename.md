---
id: STATBUS-005
title: Build the 28-slug grip-map for the install-recovery rename
status: Done
assignee: []
created_date: '2026-06-07 11:25'
updated_date: '2026-06-07 11:50'
labels:
  - install-recovery
  - rename
  - review
dependencies: []
references:
  - test/install-recovery/scenarios/
  - tmp/operator-slug-grip-map.md
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For each of the 28 canonical scenario slugs (basenames in test/install-recovery/scenarios/*.sh), list every file:line in the repo (excluding tmp/ and .git/) where that exact slug appears, e.g. `rg -n -F '<slug>'`. Goal: confirm each slug "grips" everywhere it should (own file, run.sh, README, diagram, comments) and flag any slug that appears ONLY in its own file (potential orphan) or in zero diagram files.

Partial artifacts from the prior session may exist (tmp/operator-slug-grip-map.md, tmp/grip-*.txt). Dispatched last session but never reported before the crash. Recovered from harness task #45.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Grip-map written with a section per slug listing every file:line it appears at
- [ ] #2 Any orphan slug (appears only in its own file) or zero-diagram slug is explicitly flagged
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verdict (2026-06-07): PASS. The operator's grip-map (tmp/operator-slug-grip-map.md) survived the crash and covers all 28 slugs (8–19 files each). Orphans: NONE — every slug grips across its scenario file + run.sh + README + harness code + ≥1 diagram. Zero-diagram slugs: only `0-happy-install` (in no doc/diagrams/* file) — likely the happy-path baseline; whether it warrants a diagram TEST note is a diagram-truth question → routed to STATBUS-001. My dev.sh + release-gates fixes only ADD refs (no slug became more orphaned), so the pre-crash findings still hold.
<!-- SECTION:NOTES:END -->
