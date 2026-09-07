---
id: STATBUS-357
title: >-
  https-only egress scenario: a box whose network blocks outbound HTTP must install and upgrade (the Albania shape)
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-07 07:02'
labels:
  - harness
  - install
  - upgrade
  - fidelity
dependencies:
  - STATBUS-339
references:
  - install.sh
  - test/install-recovery/lib/vm-bootstrap.sh
  - test/install-recovery/scenarios/0-happy-upgrade.sh
  - cli/internal/upgrade/github.go
  - cli/internal/upgrade/ghcr.go
priority: medium
type: task
ordinal: 350000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

Albania's network drops or rejects all outbound plain-HTTP traffic. To
install there, the owner had to make every outbound fetch HTTPS by hand. That
hack is not tested: nothing in the 15 fleet scenarios or 32 arcs runs on a
box that cannot speak HTTP outward, so a future change that reintroduces one
plain-HTTP fetch (an apt mirror, a redirect that lands on http://, a docker
pull through an http registry mirror, an ACME http-01 challenge) would pass
every test and fail in Albania.

## Ground truth (2026-09-07)

- Product code reaches out to `https://github.com`, `https://api.github.com`,
  and `https://ghcr.io` only (install.sh, cli/internal/upgrade/github.go,
  ghcr.go). The only `http://` literals in product code are loopback or
  docker-internal (`127.0.0.1`, `proxy:80`, `.local`).
- The owner's Albania hack is not yet located in code by this ticket; step 1
  is to find and record it (it may be an install.sh switch, an
  `.env.config` entry, or an ops note). Until it is written down here, the
  scenario cannot know what it is protecting.
- Harness VMs bootstrap through `test/install-recovery/lib/vm-bootstrap.sh`,
  which is where an egress rule would be applied.

## Work

1. **Locate the hack.** Read install.sh, ops/, doc/, and the Albania box's
   notes; write in this ticket exactly which fetches were plain HTTP before and
   what forces them to HTTPS now. If it is only operator discipline (nothing in
   code), say so; the scenario then guards the current all-HTTPS state.
2. **One new fleet scenario** `X-https-only-egress` (name per the phase
   convention of its siblings): after VM bootstrap and before install, apply
   an egress rule that REJECTS outbound TCP port 80 (`iptables -A OUTPUT -p
   tcp --dport 80 -j REJECT`, made persistent for the VM's life). Then run
   the ordinary install at the dynamic baseline and the ordinary upgrade to
   the tagged candidate, exactly like `0-happy-upgrade`. Any plain-HTTP fetch
   fails fast and the scenario goes red naming it.
3. Prefer REJECT over DROP so failures are immediate, not 2-minute timeouts;
   note in the header that Albania's real network may DROP, and that REJECT
   is the stricter, faster proxy for it.
4. The scenario must be in `--print-selected` (default suite) so the
   orchestrator runs it on every candidate that touches install/upgrade
   payload.

## Acceptance

1. The hack is documented in this ticket with file and line references, or
   its absence is stated.
2. The scenario is listed, selected, and green on a real RC tag in the
   install-recovery harness (rides the next paid run after it lands; do not
   cut an RC for it alone).
3. A deliberate plain-HTTP fetch injected into a scratch copy of install.sh
   makes the scenario red with a message naming the URL (proves the guard
   bites).

## Out of scope

Certificates and TLS for the box's OWN listeners (that is STATBUS-358).
Standalone deployment mode on a harness VM (needs a harness-safe
certificate first; also STATBUS-358).
<!-- SECTION:DESCRIPTION:END -->
