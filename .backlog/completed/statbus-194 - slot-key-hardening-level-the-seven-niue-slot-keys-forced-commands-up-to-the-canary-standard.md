---
id: STATBUS-194
title: >-
  slot-key-hardening: level the seven niue slot keys' forced-commands up to the
  canary standard
status: Done
assignee: []
created_date: '2026-07-20 11:40'
updated_date: '2026-07-20 12:39'
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
- [x] #1 All seven slot keys carry the hardened prefix (command="/usr/local/bin/sshdo" + no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc); before/after lines recorded on this ticket
- [x] #2 Per-key verification after EACH edit: allowed probe succeeds AND arbitrary command refused, on the forced-command path
- [x] #3 CI deploy path proven intact after the change (one real workflow ssh or equivalent sshdo probe per slot)
- [x] #4 authorized_keys backed up before the first edit; backup path recorded here
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-20 12:39
---
EXECUTED 2026-07-20 (foreman, King-granted root@niue session). BEFORE: all seven slot keys bare `command="/usr/local/bin/sshdo"` (each file: 3 human keys untouched + 1 CI key line). AFTER: CI key line on all seven = `command="/usr/local/bin/sshdo",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc` (the canary standard). METHOD, per key one at a time: backup to authorized_keys.bak-20260720-statbus194 in each user's .ssh (AC#4); sed the one CI line; verify hardened=1/bare=0 lines; ssh-keygen -lf parse = 4 keys; sshdo allowed probe (SSH_ORIGINAL_COMMAND ci-deploy-status 40-hex — dev rc=20 correct verdict; the six others rc=127 script-absent, which PROVES sshdo allowed+executed the command; the boxes predate the script — the deploy workflows' ruled two-phase 127 branch covers this); refused probe `ls /` → 'not in allowlist' on all seven (AC#2). AC#3 real-CI proof: deploy-to-dev run 29742695414 SSHed as statbus_dev THROUGH the hardened line — apply-latest executed, poke green (poke-only path with the loud self-expiring notice: dev's installed sb predated the deployed_commit emit), and the box then CONVERGED: row 360738 commit b15eb24d2 completed 12:38:14. The six other slots carry byte-identical line transformations + the equivalent sshdo probes; their next routine deploys ride the same hardened form. Bonus finding en route: the first deploy attempt was refused by the images-ready freshness gate (local backlog auto-commits unpushed to master — the STATBUS-184 genre, caught live by the deploy path's own gate); resolved by syncing master properly and redeploying. Scripts + outputs: tmp/statbus194-*.{sh,out}.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All seven niue slot CI deploy keys leveled up from the bare forced-command to the canary-standard hardened prefix (command="/usr/local/bin/sshdo" + no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc), executed one key at a time with per-key backups, parse checks, and allowed/refused sshdo probes; human keys untouched. Proven end-to-end by a real CI deploy (run 29742695414) SSHing through the hardened statbus_dev line, with the dev box converging on the deployed commit (row 360738 completed). Backups: authorized_keys.bak-20260720-statbus194 in each slot user's ~/.ssh.
<!-- SECTION:FINAL_SUMMARY:END -->
