---
id: STATBUS-492
title: >-
  The prepare instruction should run as root in a root login shell so root never
  writes into the operator home
status: To Do
assignee: []
created_date: '2026-10-13 12:29'
labels:
  - install
  - hardening
dependencies: []
priority: high
type: bug
ordinal: 418204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 during the Uganda preparation. The owner ran `sudo ./setup.sh` from the operator home. Plain sudo runs as root but keeps the invoking situation, so anything root writes can land inside the non-root home as root-owned files, which later breaks the very user the installer runs as (statbus). The owner instruction: use `sudo -i`, a root login shell with HOME=/root and a clean environment, so root writes only where root belongs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The published prepare instruction runs the script as root inside a root login shell (sudo -i or an equivalent that sets HOME to the root home and clears the invoking environment). Checked by the instruction text plus a transcript showing the HOME in effect.
- [ ] #2 If the script is invoked with plain sudo from an operator home, it either refuses and names the correct invocation, or writes every file it owns outside that home and says where. Checked by a run transcript for that invocation.
- [ ] #3 After a fresh preparation, no file owned by root exists anywhere in the operator home. Checked by an ownership inspection recorded in the ticket.
<!-- AC:END -->
