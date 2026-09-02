---
id: STATBUS-336
title: >-
  offchannel-sweep-escapes: the CI-not-ready reset recreates a sweepable row,
  and filtered-tag pruning strips live off-channel tags
status: To Do
assignee: []
created_date: '2026-09-02 08:17'
labels:
  - upgrade
  - defect
dependencies: []
priority: high
type: bug
ordinal: 329000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two escapes found by adversarial review of the READY-cutoff fix (Sol xhigh, 2026-09-02), both letting the system retire or corrupt a deliberately scheduled off-channel row:
1. The CI-not-ready unschedule reset (cli/internal/upgrade/service.go:6295) returns a claimed row to state='available' with its old tags and discovered_at; the next daemon restart's off-channel sweep then retires it to skipped — orphaning the operator's manual schedule. Narrow: needs manual off-channel schedule + images-not-ready + restart.
2. Discovery passes the CHANNEL-FILTERED tag list into pruneDeletedTags (service.go:4687), whose contract is "drop tags deleted in git": an off-channel tag exists in git but not in the filtered list, so a scheduled off-channel row's tag is falsely stripped on an ordinary discovery tick, silently demoting it to commit status. Not narrow — silent identity corruption.

Fix: (a) pruneDeletedTags receives the unfiltered git tag list (its contract is git existence, not channel membership); (b) the CI-not-ready reset must not recreate a sweepable row — either re-stamp discovered_at=now() on reset (making it post-cutoff for the next boot) or preserve schedule intent; builder chooses the honest minimal shape with a test per hole.

Acceptance: a manually scheduled off-channel row survives (tag intact, not skipped) across images-not-ready → unschedule → daemon restart → discovery tick; pruneDeletedTags proven to never strip a tag that exists in git; existing off-channel sweep tests stay green.
<!-- SECTION:DESCRIPTION:END -->
