---
id: STATBUS-495
title: >-
  The SSH stage must confirm remote access before it disables password
  authentication
status: In Progress
assignee: []
created_date: '2026-10-13 13:07'
updated_date: '2026-10-13 13:07'
labels:
  - install
  - hardening
dependencies: []
priority: high
type: bug
ordinal: 421204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 in the Uganda prepare run, Stage 2. The stage printed "WARNING: Ensure you have console access or SSH keys set up!", then wrote /etc/ssh/sshd_config.d/hardening.conf with PasswordAuthentication no, and verified only that the two lines were present in that file. It proved the door was locked and never proved the operator held a key. The keys are installed by populate_authorized_keys, which runs in a LATER stage, so the order was lock-then-distribute: one failed key fetch (network, rate limit, wrong username) would leave the box reachable only through the console provider. Owner decision 2026-10-13: establish access first, have the person prove it from a second terminal with the safe default being no, and only then close the door; if no keys exist and no GitHub username is configured, refuse before touching SSH. The stage also produced a second, smaller fault: it restarted ssh.service without systemctl daemon-reload, which is why the run showed "unit file ... changed on disk".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Before SSH is changed, the stage tells apart the three cases: keys already present for the login account (say so, install nothing), no keys but GITHUB_USERS names accounts (install them, say what was installed), no keys and no GITHUB_USERS (refuse, name the configuration entry, change nothing). Checked by test/install-recovery/tests/setup-remote-access-gate-test.sh cases 1, 3, 4.
- [x] #2 A failed key installation refuses before prompting and changes nothing. Checked by case 3b.
- [x] #3 In every case that proceeds, the operator is asked to connect from a second terminal and answer, with the default NO, and NO leaves SSH unchanged and records the run as not hardened. Checked by case 1 (refusal) and case 2 (proceed) plus the stage reading, where a refused gate runs verify "Remote access confirmed before hardening" false.
- [x] #4 The stage verifies that at least one authorized key exists for the login account after the change, not only that the drop-in contains the two lines. Checked by reading the stage verification block.
- [x] #5 The restart no longer warns: systemctl daemon-reload runs before restarting ssh. Checked by reading the stage; the warning is absent from the next real run.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-13, implemented and evidenced by the coordinator directly (the owner observed that delegated agents were slow on small fixes). RED: STATBUS_SETUP_SCRIPT=<HEAD copy> bash test/install-recovery/tests/setup-remote-access-gate-test.sh -> "FAIL ensure_remote_access is not defined", rc=1. GREEN: five PASS lines, rc=0 (existing keys recognised and no refuses; confirmed access proceeds installing nothing; missing keys installed from GITHUB_USERS then confirmed; a failed key install refuses before asking; no keys and no GITHUB_USERS refuses naming the configuration entry). bash -n parses. Wired into .github/workflows/harness-selftest.yaml. Test harness note: the gate must be run in the current shell, not in a command substitution, or the stubs side effects never reach the assertions — the first draft got that wrong and was fixed before the green run. Deliberate simplification: the login account checked is SERVICE_USER (default statbus).
<!-- SECTION:NOTES:END -->
