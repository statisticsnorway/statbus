---
id: STATBUS-488
title: >-
  The prepare path fetches the setup script from master instead of the release
  being installed
status: To Do
assignee: []
created_date: '2026-10-13 12:28'
labels:
  - install
  - fidelity
  - docs
dependencies: []
priority: high
type: bug
ordinal: 414204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 during the owner installation in Uganda. The box was prepared with `curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/ops/setup-ubuntu-lts.sh`, that is, master rather than a release. So the code that hardens and prepares a production box is untagged, unreviewed and free to drift from the release that is then installed on it. Owner decision 2026-10-13: the operator path must pick the setup script that belongs to the release being installed, not whatever master holds.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The published prepare instruction resolves setup-ubuntu-lts.sh from the release or channel the operator is installing, the same way install.sh resolves the program and the checkout, never from the master branch. Checked by reading the published step and by the URL or path it produces for a named version.
- [ ] #2 Preparing a box for a named older release uses that release copy of the script, verified by comparing the fetched file with the tag contents. Checked by the comparison being recorded in this ticket.
- [ ] #3 No operator-facing instruction in the repository or on the site tells anyone to fetch master; any such text is corrected. Checked by a search of the operator documentation.
<!-- AC:END -->
