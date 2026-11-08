---
id: STATBUS-592
title: Release discovery succeeds when another fetch updates the same remote ref
status: In Progress
assignee: []
created_date: '2026-11-08T09:27:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 508204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Poststable fixture commit e1842180ab7b8d56ec80ce332ee8ef2a28c29c8a hit an actual dev notification failure: git fetch --tags could not lock refs/remotes/origin/master because another fetch had already advanced it from 571336064 to e1842180a. Release42466579628 and stable v2026.11.2 remain successful and unchanged. Reproduce the competing-fetch outcome without mutating any deployment, then make release discovery converge under bounded handling while preserving credential, pruning, moved-tag and unexpected-error contracts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A deterministic behavioral regression reproduces competing fetch reference advancement and shows discovery returning the actual release tags after convergence.
- [ ] #2 Bounded handling preserves immediate or bounded explicit failure for persistent reference contention, authentication errors and moved-tag conflicts, and existing discovery tests pass.
- [ ] #3 Relevant CLI regression and exact-SHA CI pass; the failed original notification is rechecked with explicit status and conclusion and deployment state remains truthful.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Actual failed run42467077078/job128688996201 at2026-11-08T09:25:16Z. Complete failed log saved tmp/stable-config-notify-failure.log. Stable production target929fe787 is not altered by this followthrough.
<!-- SECTION:NOTES:END -->
