---
id: STATBUS-491
title: A standalone preparation should not ask for CI deploy-key credentials
status: To Do
assignee: []
created_date: '2026-10-13 12:28'
labels:
  - install
  - ux
dependencies: []
priority: medium
type: bug
ordinal: 417204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 in the Uganda prepare run. The script asks for "GitHub repo deploy-key sources for CI access" on a plain standalone box. In the owner words: this has nothing to do with a standalone install, it belongs to a cloud installation, and it is inappropriate to ask unless that intent is declared, for example with a cloud flag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The deploy-key and CI question does not appear in a plain standalone preparation. Checked by a run transcript.
- [ ] #2 It appears when, and only when, cloud intent is declared, and that flag or equivalent is documented. Checked by the cloud path transcript.
- [ ] #3 Existing cloud preparations are unaffected: every answer that was possible before remains possible with the flag. Checked by comparing the question set before and after.
<!-- AC:END -->
