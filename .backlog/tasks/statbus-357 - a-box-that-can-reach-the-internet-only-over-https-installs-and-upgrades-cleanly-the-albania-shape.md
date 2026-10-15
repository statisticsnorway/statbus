---
id: STATBUS-357
title: A box with outbound HTTPS-only policy installs and upgrades successfully
status: Done
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-10-15 19:32'
labels:
  - release-bug
  - install
  - upgrade
  - fidelity
dependencies:
  - STATBUS-363
priority: medium
type: task
ordinal: 50
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
StatBus installs and upgrades on a box whose firewall allows outbound HTTPS only, the policy many national offices run.

### Zoom out
Some offices block outbound plain HTTP. The installer and upgrade must then never depend on fetching anything over port 80. A test that simply blocks port 80 also breaks StatBus's own health checks, because Docker reaches its containers through local and private addresses. So the proof blocks port 80 to public destinations only, while loopback and private ranges stay open: exactly the policy an office would have. The proof must run on a real hardened guest, and a deliberate HTTP fetch must turn it red, or a passing run proves nothing.

### Zoom in
- **Packet model (`bdbcd8247`, from `684945e11` and `3eb69eeca`):** with Docker's default `userland-proxy`, a request to `127.0.0.1:3010` is not NATed; `docker-proxy` opens a new connection to the container's private IP. The rule therefore exempts destination ranges: `ip daddr != { 10.0.0.0/8, 127.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 80 reject`, with the IPv6 equivalent.
- **Ported to LXD and finished under STATBUS-485 (Done):** `lib/lxd-backend.sh` applies the same rule as `lib/vm-bootstrap.sh`; `https-only-egress-test.sh` and `https-only-egress-mutation-test.sh` run in Harness Selftest (`fc95698cf`); the mutation test fetches a public HTTP URL and requires the contract to fail naming it.
- **Real run:** `test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md`. Verdict PASS: on-demand LXD fork against `v2026.10.0-rc.20`, upgrade from a v2026.09.3 checkpoint, 2026-10-13 12:26-12:32 UTC, Ubuntu 26.04.1, nft rules as listed inside the guest. It was driven from a workstation, so there is no Actions run URL.
- **In the gate:** `ebb0ee66f` removed `HARNESS_SKIP_DEFAULT`; `0-https-only-egress` is now in the default LXD fault set.
- **Re-run 2026-10-15:** both offline tests pass locally.

### Closing review
- **Memory:** none needed.
- **Documentation:** the evidence file records the method and result.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 On a real Ubuntu 26.04 guest with port 80 refused to public destinations, the private-destination exemption keeps the Docker-published health path working, and the v2026.09.3 baseline upgrades to the candidate (`STATBUS-357-https-only-nat-1.md`, PASS at v2026.10.0-rc.20)
- [x] #2 `test/install-recovery/tests/https-only-egress-mutation-test.sh` introduces a public HTTP fetch and observes the contract fail naming that URL, on both backends
- [x] #3 `test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md` records the candidate, the guest image, the nft rules as listed, the health path, and the install and upgrade results
- [x] #4 `0-https-only-egress.sh` no longer carries `HARNESS_SKIP_DEFAULT` and runs in the default LXD fault set (`ebb0ee66f`)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1, AC3:** `test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md`, PASS 2026-10-13.
- **AC2:** mutation test in Harness Selftest (`fc95698cf`; Harness Selftest `38297872803`); re-run locally 2026-10-15, pass.
- **AC4:** `ebb0ee66f`; no `HARNESS_SKIP_DEFAULT` in the scenario on master.
- **Done:** all criteria met; the remaining work had been broken down and finished as STATBUS-485 (Done).
<!-- SECTION:NOTES:END -->
