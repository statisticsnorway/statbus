---
id: STATBUS-578
title: Preserve requested detached dev command and arguments
status: In Progress
assignee: []
created_date: '2026-11-07T20:11:00Z'
labels: []
dependencies: []
type: bug
ordinal: 505204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Detached dispatch shifts the already parsed action again, so detached test fast launches fast instead of test fast. Keep scope to exact child command and arguments and safe acceptance coverage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The public detached test fast invocation starts the child with test and fast intact.
- [ ] #2 Detached execution preserves argument boundaries and records explicit child exit evidence in a bounded actual tmux regression.
<!-- AC:END -->
