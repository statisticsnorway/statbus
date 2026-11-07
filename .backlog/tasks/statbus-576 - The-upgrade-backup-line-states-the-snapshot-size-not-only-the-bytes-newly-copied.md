---
id: STATBUS-576
title: >-
  The upgrade backup line states the snapshot size, not only the bytes newly
  copied
status: To Do
assignee: []
created_date: '2026-11-07T19:07:00Z'
labels:
  - upgrade
  - ux
dependencies: []
ordinal: 503204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The upgrade's backup line reports the bytes newly written by the incremental rsync (the drop in free disk space), so a box whose database barely changed since its last upgrade reads "Backing up database ... ok (0 B in 12.9s)". The snapshot itself is complete (53 GB at ~/statbus-upgrade-snapshots/pre-upgrade-active on Norway, run U 2026-11-07 19:02 UTC), but an operator reads "0 B" as "nothing was backed up".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The line names the snapshot's size and what changed, e.g. 'ok (53 GB snapshot, 0 B changed, 12.9s)'; a unit test pins the wording for a full first copy and for an unchanged database
<!-- AC:END -->
