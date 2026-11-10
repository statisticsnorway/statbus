---
id: STATBUS-602
title: >-
  Setup's summary names the SSH ports the firewall opens, and the manual box can
  test a non-standard SSH port
status: In Progress
assignee: []
created_date: '2026-11-10T09:56:00Z'
updated_date: '2026-11-10T10:00:00Z'
labels:
  - setup
  - installer
dependencies: []
priority: medium
type: bug
ordinal: 518204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star

An operator reading the end of a setup run knows exactly which ports the firewall lets in, including the port SSH really listens on, without running ufw status.

### Zoom out

The security-tools stage allows SSH on the standard port through the OpenSSH profile and on every other port sshd listens on, and its log says so. Its description and the final summary do not: the description promises "Allow SSH, HTTP, HTTPS, PostgreSQL through firewall" and the summary says "CrowdSec intrusion detection and UFW firewall active". On Uganda, where SSH listens on 713, nothing at the end of the run tells the operator that 22 (OpenSSH) and 713 were opened. The firewall state on Uganda is correct; only the reporting is incomplete (owner, 2026-11-10, after the idempotency rerun). The manual box can only rehearse the standard-port case, because it always has SSH on 22.

### Zoom in

`ops/setup-ubuntu-lts.sh`: the security-tools stage description and its summary line name the ports opened, taken from `ssh_listen_ports` (for Uganda: OpenSSH (22) and 713/tcp, plus 80, 443, 5432). The summary table in `STAGES` holds a fixed line per stage, so the stage records its ports for the summary. `ops/manual-box.sh` gains a way to move sshd to another port before setup, so the next manual-box run exercises the custom-port path. Not to be rerun on Uganda; verified on the manual box next run (owner).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 test/install-recovery/tests/setup-summary-truth-test.sh (or setup-ssh-port-firewall-test.sh) fails against the current setup and passes after: with sshd on 713 the security-tools summary line names OpenSSH (22) and 713/tcp, and with sshd on 22 only it names OpenSSH (22) alone
- [x] #2 The security-tools stage description names the SSH port(s) it will open, from the ports sshd listens on
- [x] #3 ops/manual-box.sh can put sshd on a non-standard port before setup, documented in its guide
- [ ] #4 [Owner] On the next manual-box run with SSH on a non-standard port, the setup summary names both ports and ufw status matches
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-10 10:00 UTC RED e924a85fc (setup-ssh-port-firewall-test.sh section 12: 3 new checks fail on the parent, tmp/602-red.log), GREEN a0df9c5bc (19 PASS, tmp/602-green.log; setup-summary-truth-test passes): the stage description reads 'Allow SSH on OpenSSH (22) and 713/tcp, plus HTTP, HTTPS and PostgreSQL' and the summary 'CrowdSec intrusion detection and UFW firewall active, allowing OpenSSH (22), 713/tcp (SSH), 80/tcp, 443/tcp, 5432/tcp'. Manual box: 63444ac96 adds MANUAL_BOX_SSH_PORT (ssh.socket drop-in via cloud-init; cloud-config validated as YAML). Two other setup tests fail on macOS only (BSD script/sed), identically without this change; CI's Linux harness runs them. Remaining: AC4, the next manual-box run with MANUAL_BOX_SSH_PORT=713 (owner).
<!-- SECTION:NOTES:END -->
