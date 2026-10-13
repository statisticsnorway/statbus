---
id: STATBUS-497
title: >-
  Uganda box: rerun the prepared installer after the next release and record the
  observations this depends on
status: In Progress
assignee: []
created_date: '2026-10-13 13:16'
labels:
  - install
  - uganda
  - release
dependencies: []
priority: high
type: task
ordinal: 423204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY THIS EXISTS. Four findings from the Uganda installation have acceptance criteria that only a real box can satisfy, and the owner will rerun the installer on that remote machine after the next release. This ticket is the concrete step so it is not forgotten, and so each dependent ticket can name where its observation comes from. It is deliberately In Progress: the work is scheduled, not done. WHAT TO COLLECT on that rerun: (1) STATBUS-492 criterion 1, the published preparation instruction shown running in a root login shell with a transcript showing the HOME in effect; (2) STATBUS-492 criterion 3, an ownership inspection proving no file owned by root is left anywhere in the operator home after a fresh preparation; (3) STATBUS-487 criterion 5, the operator-facing output of the install on a box where Docker is unreachable, which must name Docker and the remedy instead of the disk-space sentence. Paste the raw output into this ticket and into each dependent ticket, then check that ticket criteria there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 STATBUS-492 criterion 1 is satisfied with a real transcript from the box: the preparation ran in a root login shell and the HOME in effect is recorded.
- [ ] #2 STATBUS-492 criterion 3 is satisfied with an ownership inspection from that box showing no root-owned file in the operator home.
- [ ] #3 STATBUS-487 criterion 5 is satisfied with the install output from that box, quoted verbatim, showing the Docker cause named with its remedy.
- [ ] #4 Each dependent ticket names this ticket as the source of its observation.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-13 on the owner instruction: the installer rerun on the remote Uganda machine happens after the next release, and this must exist as a tracked item rather than a remembered intention. Related: 487 (Docker prerequisite named), 492 (root login shell and no root-owned files in the home), 486 (workaround removal) and the release path.
<!-- SECTION:NOTES:END -->
