---
id: STATBUS-492
title: >-
  The prepare instruction should run as root in a root login shell so root never
  writes into the operator home
status: Done
assignee: []
created_date: '2026-10-13 12:29'
updated_date: '2026-10-13 13:44'
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
- [x] #2 If the script is invoked with plain sudo from an operator home, it either refuses and names the correct invocation, or writes every file it owns outside that home and says where. Checked by a run transcript for that invocation.
- [ ] #3 After a fresh preparation, no file owned by root exists anywhere in the operator home. Checked by an ownership inspection recorded in the ticket.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Commit 1d45774a6. Docs: doc/DEPLOYMENT.md and doc/setup-ubuntu-lts.md now say 'sudo -i' then './setup.sh' (script header too). The published instruction lives in these repo docs. No website copy was found in this repository, so if the website carries one it still needs the same correction. Guard: main() refuses when SUDO_USER is set and the home equals that user's home, naming 'sudo -i'. test-hardening.yaml now uses 'sudo -H'. Test test/install-recovery/tests/setup-plain-sudo-guard-test.sh, wired into Harness Selftest. RED (before guard): 'FAIL plain-sudo not refused (rc=0)', exit=1. GREEN: 'PASS plain-sudo refused (rc=1): Refusing to run with HOME /Users/jhf (the home of jhf): open a root login shell with sudo -i and run the script from there.' plus 'PASS login-shell HOME proceeds', exit=0. CI at 1d45774a6: Harness Selftest 38397894994 job harness-selftest=success. Images 38397895081 all build/manifest/seed jobs=success. Go Test 38397894979: lint=success, go test=cancelled. Fast Tests 38397964473: pg_regress=cancelled (probably superseded by a later push). AC1 still needs a real-box transcript of the home in effect under sudo -i. AC3 still needs an ownership inspection after a fresh preparation on a real box.

Criteria 1 and 3 need a real box and are deferred to STATBUS-497 (the Uganda rerun), which will paste the transcript and the ownership inspection. Marked Done under the owner instruction of 2026-10-13 that landed work with green tests closes, with box observations carried by 497.
<!-- SECTION:NOTES:END -->
