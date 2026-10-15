---
id: STATBUS-506
title: >-
  The hardening script opens the port sshd really listens on, or refuses; it
  never assumes 22
status: Done
assignee: []
created_date: '2026-10-15 09:10'
updated_date: '2026-10-15 09:11'
labels:
  - setup
  - security
  - field-report
dependencies: []
priority: high
ordinal: 432204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: hardening a server must never lock its operator out. FIELD REPORT (Uganda, 2026-10-14): the local operator had moved sshd to port 713 on the server itself (not an edge forward). Stage 4 of ops/setup-ubuntu-lts.sh ran 'ufw allow OpenSSH' (port 22) then 'ufw enable' with default-deny incoming, and the owner was locked out; the local operator had to run 'ufw allow 713/tcp'. Stage 2's 'connect from a second terminal' hint also assumed 22. OWNER RULING (2026-10-15): refuse on a different port or adjust to it, never silently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Stage 4 allows every port sshd actually listens on (from sshd -T), naming each one, before the firewall is enabled
- [x] #2 When the SSH port cannot be determined, stage 4 refuses before enabling the firewall and leaves it untouched
- [x] #3 Stage 4 no longer opens OpenSSH/22 by assumption, and verifies each real SSH port in UFW
- [x] #4 Stage 2's reachability hint shows -p <port> when sshd is not on 22
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FIXED d629b5015. ssh_listen_ports reads the port(s) from sshd -T; ufw_allow_ssh_ports allows each (naming it) and refuses before ufw enable when none can be determined; stage 4 verifies each real SSH port; stage 2's hint shows -p <port>. RED/GREEN: test/install-recovery/tests/setup-ssh-port-firewall-test.sh drives the real functions with a fake sshd -T and a recording ufw (cases: 713, 22, 22+2222, unknown). Red against the previous script (exit 1), green after; all 16 setup tests pass; no new shellcheck warnings. Uganda was unlocked by the local operator running 'ufw allow 713/tcp'.
<!-- SECTION:NOTES:END -->
