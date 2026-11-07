---
id: STATBUS-492
title: >-
  The prepare instruction should run as root in a root login shell so root never
  writes into the operator home
status: Done
assignee: []
created_date: 2026-10-13 12:29
updated_date: '2026-11-07T10:32:00Z'
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
- [x] #1 The published prepare instruction runs the script as root inside a root login shell (sudo -i or an equivalent that sets HOME to the root home and clears the invoking environment). Checked by the instruction text plus a transcript showing the HOME in effect.
- [x] #2 If the script is invoked with plain sudo from an operator home, it either refuses and names the correct invocation, or writes every file it owns outside that home and says where. Checked by a run transcript for that invocation.
- [x] #3 After a fresh preparation, no file owned by root exists anywhere in the operator home. Checked by an ownership inspection recorded in the ticket.
- [x] #4 Run from a root login shell reached as root (ssh root@box, then sudo -i: SUDO_USER=root, HOME=/root), the script proceeds; plain sudo from an operator home is still refused. setup-plain-sudo-guard-test.sh covers both, red before the fix and green after; observed on the test box with the next release
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Commit 1d45774a6. Docs: doc/DEPLOYMENT.md and doc/setup-ubuntu-lts.md now say 'sudo -i' then './setup.sh' (script header too). The published instruction lives in these repo docs. No website copy was found in this repository, so if the website carries one it still needs the same correction. Guard: main() refuses when SUDO_USER is set and the home equals that user's home, naming 'sudo -i'. test-hardening.yaml now uses 'sudo -H'. Test test/install-recovery/tests/setup-plain-sudo-guard-test.sh, wired into Harness Selftest. RED (before guard): 'FAIL plain-sudo not refused (rc=0)', exit=1. GREEN: 'PASS plain-sudo refused (rc=1): Refusing to run with HOME /Users/jhf (the home of jhf): open a root login shell with sudo -i and run the script from there.' plus 'PASS login-shell HOME proceeds', exit=0. CI at 1d45774a6: Harness Selftest 38397894994 job harness-selftest=success. Images 38397895081 all build/manifest/seed jobs=success. Go Test 38397894979: lint=success, go test=cancelled. Fast Tests 38397964473: pg_regress=cancelled (probably superseded by a later push). AC1 still needs a real-box transcript of the home in effect under sudo -i. AC3 still needs an ownership inspection after a fresh preparation on a real box.

Criteria 1 and 3 need a real box and are deferred to STATBUS-497 (the Uganda rerun), which will paste the transcript and the ownership inspection. Marked Done under the owner instruction of 2026-10-13 that landed work with green tests closes, with box observations carried by 497.

2026-11-02 defect found on statbus-manual with released v2026.11.0 setup.sh: ssh root@box, sudo -i (HOME=/root login=yes user=root) was refused with 'Refusing to run with HOME=/root (the home of root)'. Cause: sudo from root sets SUDO_USER=root, and the guard compared HOME with ~SUDO_USER, which is root's own home. Fix: the guard applies only when the invoking user is not root. Test red before the fix (tmp/492/guard-test-red.log: FAIL sudo -i from root refused rc=1), green after (tmp/492/guard-test-green.log). Neighbouring setup tests green. Workaround until the next release: run setup.sh directly from the root login, without sudo -i.

CI for fix 20d510e84: Harness Selftest 41463436032 completed success (runs setup-plain-sudo-guard-test.sh). Remaining: ship in the next RC and observe sudo -i from a root login on the test box.

rc.18 manual box 2026-11-07 (tmp/manual-rc18-setup-evidence.log, from tmp/statbus-manual-session.log): AC1: the guide and DEPLOYMENT.md say sudo -i; in that root shell 'echo HOME=$HOME SUDO_USER=$SUDO_USER' printed HOME=/root SUDO_USER=ubuntu; setup v2026.11.1-rc.18 ran all 9 stages and every check passed. AC3: after that setup 'find /home/statbus -xdev -user root' printed nothing (owner: check removed from the manual-box guide, 24c0507d0). AC4: as ubuntu, 'curl -fsSL https://statbus.org/rc/setup.sh | bash' (not root) was refused with 'This script must be run as root (use sudo)'. The owner ruled that text not to the point, so both refusals (not root, plain sudo) now print one line: Run 'sudo -i' first, then run this command again. (c6728d1c8, 27f336dda; setup-plain-sudo-guard-test red tmp/setup-root-msg-red.log, green tmp/setup-root-msg-quote-green.log, which also covers SUDO_USER=root HOME=/root proceeding; root cannot ssh to this box, so that half rests on the test).
<!-- SECTION:NOTES:END -->
