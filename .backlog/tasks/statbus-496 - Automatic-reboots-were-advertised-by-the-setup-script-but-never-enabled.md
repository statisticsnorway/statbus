---
id: STATBUS-496
title: Automatic reboots were advertised by the setup script but never enabled
status: In Progress
assignee: []
created_date: '2026-10-13 13:12'
updated_date: '2026-10-13 13:13'
labels:
  - install
  - hardening
dependencies: []
priority: high
type: bug
ordinal: 422204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 reviewing the Uganda prepare run, Stage 3 (automatic updates). The stage announced "Configure reboot time if needed (03:00 + random delay)" and wrote Unattended-Upgrade::Automatic-Reboot-Time "03:15", but never wrote Unattended-Upgrade::Automatic-Reboot "true". unattended-upgrades defaults that switch to false, so the time was inert and the box would never have rebooted: the operator was promised a reboot window that did not exist. OWNER DECISION 2026-10-13: this is an oversight, the reboot is meant to be enabled deliberately, and it is authorized as a fix now. Enabling it means the box reboots at the configured hour when /var/run/reboot-required is present after an upgrade run, which is the intended behaviour on these boxes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The written configuration enables automatic reboots and names an hour. Checked by test/install-recovery/tests/setup-auto-reboot-test.sh assertions 1 and 2.
- [x] #2 The text the stage prints names the same hour the configuration writes, so the promise and the behaviour cannot drift apart again. Checked by assertion 3.
- [x] #3 The test runs in CI rather than only by hand. Checked by the Harness Selftest workflow listing it on a push touching test/install-recovery/**.
- [x] #4 The interaction with a clean database stop is recorded rather than silently ignored: an unattended reboot at the configured hour lands on the stop path that STATBUS-427 exists to make clean.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-13, fixed and evidenced by the coordinator in one pass under the owner authorization. RED: STATBUS_SETUP_SCRIPT=<HEAD copy> bash test/install-recovery/tests/setup-auto-reboot-test.sh -> the switch missing and the prompt naming no hour (rc=1). GREEN: three PASS lines, rc=0 (reboots enabled; hour 03:15 configured; the stage announces 03:15). bash -n parses. Wired into .github/workflows/harness-selftest.yaml. One self-correction recorded for honesty: the first version of the test extracted the stage with awk /^}/, which stopped at the config block own "};" lines and hid the settings; it now ends on a line that is exactly "}".
<!-- SECTION:NOTES:END -->
