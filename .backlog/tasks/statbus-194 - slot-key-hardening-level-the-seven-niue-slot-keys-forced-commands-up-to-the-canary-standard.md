---
id: STATBUS-194
title: >-
  slot-key-hardening: level the seven niue slot keys' forced-commands up to the
  canary standard
status: To Do
assignee: []
created_date: '2026-07-20 11:40'
labels:
  - ops
  - security
  - ci
  - niue
dependencies: []
references:
  - ops/github-runner/runner-health-K2-runbook.md
priority: medium
ordinal: 195000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every CI-held SSH key on niue carries the hardened forced-command prefix, so a leaked repo secret buys an attacker exactly one allowlisted command and no forwarding/pty side-channels.
> ORIGIN: architect S2 review on STATBUS-069 (recorded there 2026-07-15 as a K-list session item; this ticket makes it durable). King granted foreman root@niue access for this work 2026-07-20 (chat), with report + ticket updates required.
> STAGE: foreman executes in a dedicated root session — deliberately NOT bundled with the K2 canary provisioning: a broken forced-command silently locks CI out of that slot's deploys, so each key needs its own before/after verification.

THE WORK: the seven per-slot CI deploy keys in /root-managed authorized_keys on niue (statbus_tcc, statbus_dev, statbus_demo, statbus_ma, statbus_ug, statbus_et, statbus_jo) currently carry the BARE prefix `command="/usr/local/bin/sshdo"` (foreman-verified live baseline 2026-07-15). Level each UP to the canary key's hardened form: `command="/usr/local/bin/sshdo",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc`.

METHOD (per key, one at a time): backup the authorized_keys file first; edit ONE slot's line; verify ALLOWED path (SSH_ORIGINAL_COMMAND probe of an allowlisted command succeeds) and REFUSED path (arbitrary command denied) on the exact CI forced-command path; only then proceed to the next key. Finish with one real deploy-workflow exercise (or its sshdo probe equivalent) proving the CI path end-to-end.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All seven slot keys carry the hardened prefix (command="/usr/local/bin/sshdo" + no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc); before/after lines recorded on this ticket
- [ ] #2 Per-key verification after EACH edit: allowed probe succeeds AND arbitrary command refused, on the forced-command path
- [ ] #3 CI deploy path proven intact after the change (one real workflow ssh or equivalent sshdo probe per slot)
- [ ] #4 authorized_keys backed up before the first edit; backup path recorded here
<!-- AC:END -->
