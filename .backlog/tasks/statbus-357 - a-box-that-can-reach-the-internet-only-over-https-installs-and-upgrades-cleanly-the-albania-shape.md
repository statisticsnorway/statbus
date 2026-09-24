---
id: STATBUS-357
title: A box with outbound HTTPS-only policy installs and upgrades successfully
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-24 18:47'
labels:
  - harness
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
The paid VM proof applies the production Ubuntu hardening, refuses TCP port 80 to public destinations while allowing loopback and private destinations (so Docker-published health traffic keeps working), installs the baseline, and upgrades to the candidate using ordinary operator paths. It remains on demand until one real-VM run with the private-destination rule is green. After that proof and a deliberate HTTP mutation control pass, it joins the default selected set.

## Evidence, 2026-09-24

Packet model (merged in `bdbcd8247`, commits `684945e11` and `3eb69eeca`): with Docker's default `userland-proxy=true`, Docker's nat OUTPUT jump excludes loopback, so a request to `127.0.0.1:3010` is not DNATed; `docker-proxy` accepts it and opens a new host connection to the container IP (for example `172.18.0.3:80`), with no NAT. The rule therefore exempts destination scopes, not original destinations: `ip daddr != { 10.0.0.0/8, 127.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 80 reject` and `ip6 daddr != { ::1, fc00::/7, fe80::/10 } tcp dport 80 reject` (`test/install-recovery/lib/vm-bootstrap.sh:1313-1317` at master `1e96d380f`). nft 1.1.6 on the Ubuntu 26.04 VM lists the IPv4 rule in exactly that form, without `meta nfproto` (`tmp/egress-mech-check.log:33`, rc.03 mechanism run), and the rule check greps that listing.

The current scenario is explicitly on demand through `HARNESS_SKIP_DEFAULT` (`test/install-recovery/scenarios/0-https-only-egress.sh:10` at master `1e96d380f`) and delegates to the shared happy-upgrade flow. The rule and its IPv4 and IPv6 rejection probes are in `test/install-recovery/lib/vm-bootstrap.sh:1281-1334`; the offline mutation contract that checks external rejection and the loopback health path is in `test/install-recovery/tests/https-only-egress-test.sh:26-180`; and the shared Ubuntu 26.04 default is selected at `test/install-recovery/lib/vm-bootstrap.sh:91-94`, all at master `7a9cf707e`. Product external fetches use HTTPS in the bootstrap (`install.sh:624-685`), release-manifest download (`cli/internal/upgrade/github.go:202-206`), and registry base URL (`cli/internal/upgrade/ghcr.go:10-14`), all at master `7a9cf707e`. No line-specific primary Albania record or checked-in Albania workaround has been located, so earlier Albania historical assertions are withdrawn rather than treated as evidence.

The proof identity is `STATBUS-357-https-only-nat-1`. Its evidence file is `new: test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md`, which records candidate tag, harness run URL, Ubuntu image, firewall rules as listed by nft, the docker-proxy health path result, install result, and upgrade result.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-recovery/scenarios/0-https-only-egress.sh` run `STATBUS-357-https-only-nat-1` first proves on a real Ubuntu 26.04 VM that the private-destination exemption preserves the Docker-published loopback health path (docker-proxy to the container IP) while TCP/80 to public destinations is rejected.
- [ ] #2 `new: test/install-recovery/tests/https-only-egress-mutation-test.sh` introduces `http://example.com/statbus-http-egress-mutation` and observes the scenario fail while naming that URL.
- [ ] #3 `new: test/install-recovery/scenarios/0-https-only-egress.sh` run `STATBUS-357-https-only-nat-1` verifies that `new: test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md` records its successful baseline install and candidate upgrade under the corrected real-VM rule.
- [ ] #4 After criteria #1-#3, `test/install-recovery/scenarios/0-https-only-egress.sh` removes `HARNESS_SKIP_DEFAULT`, and `new: test/install-recovery/tests/https-only-egress-selection-test.sh` observes the scenario in `run.sh --print-selected`.
<!-- AC:END -->
