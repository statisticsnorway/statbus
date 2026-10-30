---
id: STATBUS-497
title: >-
  Real-box proof for fixes only a real box can confirm: preparation on the plain
  manual box, SSH and firewall rerun on Uganda
status: In Progress
assignee: []
created_date: 2026-10-13 13:16
updated_date: '2026-10-30T13:35:00Z'
labels:
  - install
  - uganda
  - release
dependencies: []
priority: high
type: task
ordinal: 423204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Fixes that only a real machine can confirm close on observation, not on reasoning.

### Zoom out
Some criteria can only be met by watching the product on a real, unprepared machine: what the published preparation does in a root login shell, what the operator home looks like afterwards, and what Stage 2 and Stage 4 do on a server with a non-standard SSH port and an existing firewall. Uganda (statbus.ubos.org) hit these first. Owner decisions 2026-10-30: Uganda is handed over, so its installer is not rerun; the preparation proof comes from a fresh preparation of the plain manual box (ops/manual-box.sh, walkthrough steps 2-4); Uganda reruns only setup Stages 2 and 4 after the next release, which changes nothing there.

### Zoom in
- **Origin, 2026-10-13:** filed so the Uganda rerun is tracked, not remembered.
- **Done already:** STATBUS-487 criterion 5 is not applicable (Docker was reachable on Uganda, v2026.10.5 installed 19/19). The 2026-10-30 Uganda read-only check found only Caddy runtime files root-owned (Implementation Notes).
- **Still to observe, after the next release:**
  1. Plain box: STATBUS-492 criteria 1 and 3 (root login shell with HOME, no root-owned file in the operator home after preparation).
  2. Uganda: setup.sh --skip-stages "0 1 3 5 6 7 8" closes STATBUS-539 AC7 and STATBUS-540 AC4.

### Closing review
- **Memory:** none. **Documentation:** none. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 STATBUS-487 criterion 5 is satisfied with the install output from that box, quoted verbatim, showing the Docker cause named with its remedy (or recorded as not applicable if Docker was reachable).
- [x] #2 Each dependent ticket names this ticket as the source of its observation.
- [x] #3 [Owner] Confirm v2026.10.1, or name a later release, as the release the Uganda rerun waits for, and record it in Implementation Notes. The confirmed release lets the rerun be scheduled; AC1-3 are filled from that run.
- [ ] #4 Plain manual box, fresh preparation with the next release: the session log shows a root login shell with HOME=/root (STATBUS-492 criterion 1)
- [ ] #5 Plain manual box, right after setup and before install: find /home/statbus -xdev -user root prints nothing (STATBUS-492 criterion 3)
- [ ] #6 Uganda, next release: setup Stages 2 and 4 rerun; the results are recorded in STATBUS-539 AC7 and STATBUS-540 AC4
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC4:** STATBUS-487 and STATBUS-492 each reference STATBUS-497 (checked 2026-10-15).
- **AC1-3:** open; they wait for the Uganda rerun.

### Release confirmed: v2026.10.2
The owner promoted v2026.10.2 on 2026-10-16. statbus.org/setup.sh and statbus.org/install.sh serve it, byte-identical to the tag.

### How to run it by hand and capture each criterion
From the release's own published instructions (ops/setup-ubuntu-lts.sh and install.sh headers at v2026.10.2):
1. **AC1, preparation.** `sudo -i` (a root login shell; plain sudo is refused). Print the home in effect with `echo "HOME=$HOME"`. Then `curl -fsSL https://statbus.org/setup.sh -o harden.sh && chmod +x harden.sh && ./harden.sh 2>&1 | tee /root/uganda-setup.log`. Keep the HOME line and the log.
2. **AC2, ownership.** After preparation: `find /home/statbus -xdev -user root`. Expected: no output.
3. **AC3, install.** As the statbus user: `curl -fsSL https://statbus.org/install.sh | bash 2>&1 | tee ~/uganda-install.log`. If Docker is unreachable, the output must name Docker and its remedy; otherwise AC3 is recorded as not applicable.
4. Paste the HOME line, the find output and the two logs back. The agent records them here and checks AC1-3.

### Also read after the install (feeds STATBUS-422 AC4)
- Open the box's login page and read the footer. It must say `Statbus version v2026.10.2`. A fresh install of a release containing 3df96b7bf is exactly what 422 AC4 asks to observe. Paste the footer line with the logs.

### Owner 2026-10-20
- The owner runs the Uganda install by hand after the next release, which follows the sql_saga 1.2 release. The steps above stand, against that release's version.

2026-10-28 fresh-setup context from the owner: the target is statbus.ubos.org on Ubuntu 26.04, accessed over a nonstandard SSH port, after earlier failed installation attempts. The current target release is v2026.10.4. Before hardening, preserve the detected SSH port, verify a second key-based login before disabling password authentication, and capture the setup and install transcripts for AC1-3 and the third-party installation review. No credentials, private keys, or nonpublic access details are to be recorded in this ticket.

Clarification: statbus.ubos.org is the local NSO server, not the ug.statbus.org preview slot. It currently has a desktop installation and an existing statbus user. The owner has approval to move to key-only access and remove the graphical workload after access is proven. Sequence: install or confirm the statbus user's authorized key, verify a second SSH login on the existing nonstandard port, keep the original session open during hardening, then disable password access and only afterwards address graphical packages. Private keys and access secrets stay out of the ticket.

2026-10-29 Uganda (statbus.ubos.org, local NSO server, Ubuntu 26.04) live run with v2026.10.4, owner driving, observed via transcript.
Setup: Stages 1, 2, 3, 5 and 7 ran and verified idempotently; Stage 0 auto-skipped (HTTP egress works); Stage 6 not offered (standalone). Stage 4 (CrowdSec and UFW) was deliberately skipped: sshd is socket-activated, ssh.socket listens on the forwarded port while sshd -T reports a different configured port, so v2026.10.4's Stage 4 would have opened the wrong port. The firewall is therefore still off. Key-only SSH was confirmed from a second terminal after Stage 2.
Installer: v2026.10.4 reached step 8 (Certificate) and stopped. The PFX password prompt went to stderr and was hidden by the terminal filter, so an Enter was read as an empty password (pkcs12: decryption password incorrect). The PFX itself is valid and covers the site name.
Fourteen setup and installer findings from this run were fixed, reviewed with red/green evidence and released in v2026.10.5-rc.01 (commits 860860abe..38ccb3003, CI test fixes a87d9d064, all CI green): socket-activated SSH port, required stages default yes, cloud-only Stage 7 wording, summary derived from stage outcomes, missing FQDN detection and installer domain default, reboot attribution, authorized-key counts, copyable next step, optional security note, quiet git fetch and checkout, prompts after the running step, certificate folder chooser with path resolution, visible PFX password prompt with retries.
Next: after stable promotion, rerun setup with the released script (Stage 4 must open the real SSH port; set the FQDN to statbus.ubos.org), then the regular installer with the PFX certificate. Then fill AC1-3.

2026-10-30 Uganda install with v2026.10.5 (owner-driven, regular scripts):
- Setup: all stages run; Stage 4 allowed 713/tcp correctly but its bouncer check failed on a stale CrowdSec key (fixed by hand, product fix STATBUS-539). Firewall now OpenSSH, 713/tcp Custom SSH, 80, 443, 5432, Zabbix 10050 from 10.10.10.253.
- Installer: 19/19 steps; custom PFX certificate (*.ubos.org) installed; first administrator created; upgrader enabled; version v2026.10.5 recorded.
- On the box: ./sb ps shows app, db (healthy), proxy, rest, worker up; curl -I -L https://statbus.ubos.org (TLS verified, no -k) gives 307 -> /login then 200 from Next.js via Caddy.
- Not yet reachable from outside: public DNS for statbus.ubos.org is 196.0.117.82, which answers as Microsoft-HTTPAPI/2.0 (404). The box is 10.10.10.58; the name resolves locally to 127.0.1.1 via /etc/hosts. UBOS IT must forward 443 and 80 (or proxy the name) to 10.10.10.58. Installer public-DNS warning queued so this is visible at install time.
- Pending: external sign-in after forwarding, setup rerun with the next release.

2026-10-30 10:05 UTC: owner signed in at https://statbus.ubos.org as the first administrator from his laptop (SSH tunnel to the box plus a temporary hosts entry), and reached the getting-started onboarding page. The installation is verified end to end; only the public route (UBOS forwarding to 10.10.10.58) remains.

2026-10-30 AC3 (STATBUS-487 criterion 5): not applicable on this box. The v2026.10.5 setup log (tmp/uganda-session.log) shows Docker installed, running, Compose installed and 'Docker usable by statbus', then the installer ran 19/19 steps without a Docker refusal. Docker was reachable, so there was no Docker-cause message to observe. AC1 (root login shell + HOME) and AC2 (find /home/statbus -xdev -user root) were not captured in this session's log: setup ran from a root prompt but no HOME line was printed, and no ownership scan was run.

2026-10-30 plan for the next release (owner decision): on statbus.ubos.org, rerun only the SSH and firewall stages as root: `sudo -i`, then `curl -fsSL https://statbus.org/setup.sh -o setup.sh && bash setup.sh --skip-stages "0 1 3 5 6 7 8"`. Expected and safe: Stage 2 rewrites the same hardening.conf and restarts ssh (port 713 is configured elsewhere and survives; answering n changes nothing); Stage 4 sees the bouncer registered and leaves its key, ufw skips existing rules, the Zabbix and IPv6 rules are never touched (only 'Custom SSH' rules for ports sshd no longer uses are removed); CrowdSec reloads, the bouncer restarts, ufw reloads, existing sessions survive; apt may upgrade crowdsec. This run closes STATBUS-539 AC7 (Stage 4 result on this box) and STATBUS-540 AC4 ('Did that connect? [y/n]' re-asks on Enter). STATBUS-537 AC5 (scripts print their tag) is box-neutral and is checked on the plain manual box (ops/manual-box.sh). The refused-key repair path is not exercised here (the key is now valid); it is covered by setup tests.

2026-10-30 12:21 UTC read-only check on statbus.ubos.org (owner, logged): HOME=/root USER=root login=yes, so the current root shell is a login shell (this does not prove how the original preparation ran). find /home/statbus -xdev -user root found 6 entries, all under ~/statbus/caddy/data/caddy (the directory itself, ocsp/, the OCSP staple for wildcard_.ubos.org, instance.uuid, locks/, last_clean.json). The Caddy proxy container writes these at runtime as root into the caddy/data bind mount (see ensureCustomCertsDirWritable in cli/cmd/cert.go; uninstall.sh removes them through a root container). They are not left by the preparation, and nothing else in the operator home is root-owned. AC1 and AC2 stay open: owner decision is to prove them on a fresh preparation of the plain manual box (ops/manual-box.sh), with the ownership scan right after setup and before install.
<!-- SECTION:NOTES:END -->
