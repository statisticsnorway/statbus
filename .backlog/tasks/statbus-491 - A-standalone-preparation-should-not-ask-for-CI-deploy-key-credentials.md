---
id: STATBUS-491
title: A standalone preparation should not ask for CI deploy-key credentials
status: Done
assignee: []
created_date: '2026-10-13 12:28'
updated_date: '2026-10-13 13:56'
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
- [x] #1 The deploy-key and CI question does not appear in a plain standalone preparation. Checked by a run transcript.
- [x] #2 It appears when, and only when, cloud intent is declared, and that flag or equivalent is documented. Checked by the cloud path transcript.
- [x] #3 Existing cloud preparations are unaffected: every answer that was possible before remains possible with the flag. Checked by comparing the question set before and after.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Mechanism: --cloud flag (or CLOUD=true) in ops/setup-ubuntu-lts.sh, documented in --help and doc/setup-ubuntu-lts.md. No existing config key expressed cloud intent. Question set BEFORE (all runs): ADMIN_EMAIL, GITHUB_USERS, GITHUB_DEPLOY_KEYS, EXTRA_LOCALES, SERVICE_USER. AFTER standalone: ADMIN_EMAIL, GITHUB_USERS, EXTRA_LOCALES, SERVICE_USER (GITHUB_DEPLOY_KEYS keeps default statisticsnorway/statbus, still settable in ~/.setup-ubuntu.env). AFTER --cloud: identical to BEFORE, same prompt text and default. Test test/install-recovery/tests/setup-cloud-deploy-key-prompt-test.sh. RED against pre-fix script (STATBUS_SETUP_SCRIPT=HEAD~ copy): FAIL standalone asks deploy-key, PASS cloud, FAIL --cloud undocumented, rc=1. GREEN: 3x PASS, rc=0. Commit d799fa0e8; Harness Selftest run 38408511911 job harness-selftest success, STATBUS-491 step success.
<!-- SECTION:NOTES:END -->
