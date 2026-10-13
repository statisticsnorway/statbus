---
id: STATBUS-490
title: >-
  The setup script prompts do not say what the answers are for or whether they
  are optional
status: Done
assignee: []
created_date: '2026-10-13 12:28'
updated_date: '2026-10-13 13:44'
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
- [x] #1 The notification email prompt states that it may be left blank and what that means. Checked by the prompt text plus a run transcript.
- [x] #2 The SSH key prompt names its purpose, operator and DevOps access to the box, and says it is unrelated to StatBus data. Checked likewise.
- [ ] #3 A blank email answer is shown to be safe: the run completes with no notifications configured. Checked by a run transcript with the answer left blank.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Commit 066b1990d. Prompts now: (email) 'Email address for system notifications (unattended-upgrades). Optional: leave blank for no unattended-upgrade notification emails:'; (ssh) 'GitHub usernames for SSH key fetching (space-separated, ED25519-only). This is operator/DevOps SSH access to the box for hardening and administration, not anything to do with StatBus data:'. Test test/install-recovery/tests/setup-prompt-purpose-test.sh drives the real setup_env with a blank email and captures the transcript. RED (before fix): FAIL email prompt, FAIL SSH prompt, PASS blank email saves ADMIN_EMAIL="" (rc=1). GREEN: 3x PASS (rc=0). CI Harness Selftest run 38404509753 job harness-selftest success, STATBUS-490 step success. AC3 partly shown: the configuration step completes with a blank email and saves ADMIN_EMAIL=""; stage 3 then writes the Mail line commented out (code branch), but a full run on a real box with blank email was not done, so AC3 stays open.

CI read at job level for the landing commit 066b1990d: Harness Selftest, Go Test, app build & lint, Images, CodeQL and Notify cloud services all success. Criterion 3 (a run transcript with the email left blank) is deferred to STATBUS-497, the Uganda rerun, where the owner leaves that answer blank; the other two criteria are checked. Marked Done under the owner instruction of 2026-10-13 (landed with green tests).
<!-- SECTION:NOTES:END -->
