---
id: STATBUS-539
title: >-
  Stage 4 always allows SSH on 22 and repairs a firewall bouncer whose key
  CrowdSec refuses
status: In Progress
assignee: []
created_date: '2026-10-30T09:22:00Z'
updated_date: '2026-10-30T09:33:00Z'
labels:
  - setup
  - security
dependencies: []
priority: high
type: bug
ordinal: 465204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
After Stage 4 the box accepts SSH on the conventional port 22 and on every port sshd really listens on, and the CrowdSec firewall bouncer is actually banning: registered, accepted by the local API and running.

### Zoom out
Stage 4 opens only the port(s) sshd listens on (STATBUS-506). Owner ruling 2026-10-30: always allow 22/tcp as well. That is the convention for this service, and leaving it closed is surprising; with nothing listening there, nothing is exposed. When sshd's ports cannot be determined, Stage 4 still refuses to enable the firewall, since 22 alone may not be where SSH listens.
STATBUS-498 made Stage 4 create a bouncer key only when api_key is empty. A key kept from an earlier install that CrowdSec no longer knows passes that check, so the bouncer runs inert.

### Zoom in
Uganda, statbus.ubos.org, 2026-10-30, v2026.10.5 setup:
- Stage 4 allowed 713/tcp (correct) and not 22.
- Verification showed '✗ Firewall bouncer registered with the local API'.
- `cscli bouncers list` was empty; crowdsec-firewall-bouncer was 'activating', restart counter 15.
- The journal showed 'process terminated with error: API error: access forbidden'.
- api_key in /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml was set: a stale key from a previous install, which this run had upgraded.

### Closing review
- **Memory:** none. **Documentation:** comments at ufw_allow_ssh_ports and the bouncer key step. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 test/install-recovery/tests/setup-ssh-port-firewall-test.sh passes: with sshd on 713, ufw sees 'allow OpenSSH' and 'allow 713/tcp comment Custom SSH' and never 'allow 22/tcp'; with sshd on 22 only, just 'allow OpenSSH'; when sshd's ports cannot be determined, nothing is allowed and the firewall is not enabled
- [x] #2 The same test passes for clean-up: a 'Custom SSH' rule for a port sshd no longer listens on (4713 while sshd is on 713) is deleted; a rule without that comment is left alone
- [x] #3 Stage 4 verification includes 'OpenSSH allowed in UFW' and the per-port check for each custom port
- [x] #4 test/install-recovery/tests/setup-crowdsec-bouncer-key-test.sh passes: with a fake cscli whose bouncer list lacks statbus-firewall-bouncer while api_key is set, Stage 4's key step re-registers statbus-firewall-bouncer (delete then add), writes the new key without printing it, and restarts the bouncer; with the bouncer already registered, the key is left untouched
- [x] #5 Stage 4 verification requires crowdsec-firewall-bouncer to be active as well as registered
- [x] #6 Both tests fail against v2026.10.5's setup script and pass after (logs in tmp/)
- [ ] #7 Rerunning the released setup's Stage 4 on statbus.ubos.org leaves statbus-firewall-bouncer valid and active, OpenSSH and 713/tcp (Custom SSH) allowed, and no 22/tcp or 4713/tcp rule
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner ruling 2026-10-30: ufw comment 'SSH' for 22/tcp, 'Custom SSH' for any other sshd port (e.g. 713). Uganda's live ufw (owner ran ufw allow 22/tcp by hand): rules 4713/tcp (no comment, from the v2026.10.4-era run), 22/tcp # SSH, OpenSSH, 80, 443, 5432, 713/tcp # SSH, 10050/tcp from 10.10.10.253 # Allow Zabbix Server; same for v6.

Root cause confirmed on statbus.ubos.org 2026-10-30 09:23 UTC: the owner ran the same sequence the fix performs (delete statbus-firewall-bouncer, add with -o raw, write api_key, restart). Result: crowdsec-firewall-bouncer 'active'; cscli bouncers list shows statbus-firewall-bouncer, 127.0.0.1, Valid ✔️, last API pull 2026-10-30T12:23:21+03:00, v0.0.36, auth api-key. Before: list empty, 'API error: access forbidden', restart counter 15. So the stale key was the whole cause, and re-registration repairs it.

Owner ruling revised 2026-10-30 09:25 UTC: standard port via the 'OpenSSH' ufw app profile (not a 22/tcp rule); other sshd ports with comment 'Custom SSH'; Stage 4 removes our own stale 'Custom SSH' rules for ports sshd no longer listens on; untagged rules are never touched. On Uganda the owner removes 4713/tcp (stale, from an earlier run) and the hand-added 22/tcp by hand.

Uganda firewall after the owner's manual clean-up (2026-10-30 09:26 UTC): OpenSSH, 80/tcp # HTTP, 443/tcp # HTTPS, 5432/tcp # PostgreSQL, 713/tcp # Custom SSH, 10050/tcp from 10.10.10.253 # Allow Zabbix Server, plus v6 counterparts. No 22/tcp or 4713/tcp. This is the target state the released Stage 4 must reproduce (AC7).

Implemented and pushed in 82e189f6c and 253621935 (revised owner ruling): ufw_allow_ssh_ports always runs 'ufw allow OpenSSH', allows every other sshd port as 'Custom SSH', and deletes 'Custom SSH' rules for ports sshd no longer listens on (rules without that comment are untouched). The stale-key repair lives in ensure_bouncer_registered: prove registration via 'cscli bouncers list', else delete + 'cscli bouncers add -o raw' + write api_key (never printed) + restart; Stage 4 verifies 'Firewall bouncer running'. Tests: setup-ssh-port-firewall-test.sh rewritten (OpenSSH/custom comments, stale 4713 deleted, uncommented 4713 kept) and new setup-crowdsec-bouncer-key-test.sh, both wired into harness-selftest.yaml. Red against v2026.10.5 in tmp/test-539-red.log, green in tmp/test-539-green.log (run in ubuntu:24.04 because macOS bash 3.2/BSD sed differ); all 18 setup-*.sh pass; bash -n clean. CI on 253621935: Harness Selftest and Go Test red only from the STATBUS-537 installer banner ('StatBus installer: development copy (not a release)') breaking install-pull-failure-test.sh and cli/cmd install_rerun_test.go; notified rabbit, nothing in this commit.
<!-- SECTION:NOTES:END -->
