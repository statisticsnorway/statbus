---
id: STATBUS-490
title: >-
  The setup script prompts do not say what the answers are for or whether they
  are optional
status: To Do
assignee: []
created_date: '2026-10-13 12:28'
labels:
  - install
  - ux
dependencies: []
priority: medium
type: enhancement
ordinal: 416204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 in the Uganda prepare run. Two prompts are not legible. The system notification email prompt gives no hint that leaving it blank is acceptable and simply means no unattended-upgrade notifications, as the owner had to know already. And "GitHub usernames for SSH key fetching" does not say that this is operator and DevOps access to the box for hardening and administration, not anything to do with StatBus data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The notification email prompt states that it may be left blank and what that means. Checked by the prompt text plus a run transcript.
- [ ] #2 The SSH key prompt names its purpose, operator and DevOps access to the box, and says it is unrelated to StatBus data. Checked likewise.
- [ ] #3 A blank email answer is shown to be safe: the run completes with no notifications configured. Checked by a run transcript with the answer left blank.
<!-- AC:END -->
