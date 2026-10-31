---
id: STATBUS-556
title: >-
  The test fleet builds its hardened base once per candidate, with every setup
  stage, and installed bases copy it
status: In Progress
assignee: []
created_date: '2026-10-31T13:44:00Z'
updated_date: '2026-10-31T13:44:00Z'
labels:
  - harness
  - release-gate
dependencies: []
priority: high
type: bug
ordinal: 479204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: every StatBus test box starts from the same hardened system an operator gets: the full setup, built once per release candidate against the current Ubuntu image, and copied by every base and scenario that needs it.

### Zoom out
The gate never ran the security-tools stage (CrowdSec + UFW), although every real box does. The skip came from the VM harness (--skip-stages=4, never explained), was copied into the LXD base as a fixed value in 0066e285f, and ignored the per-scenario switch 0-https-only-egress uses to include it (67c2977cd). The firewall bugs found on Uganda (STATBUS-506, STATBUS-539) were therefore found by a customer instead of the gate.
Smoke also hardens two fresh guests per candidate in parallel (hardened-nothing-installed and installed-<baseline>-standalone-pre), each running the same setup, instead of hardening once and copying.

Design (owner, 2026-10-31):
- The smoke ramp job builds hardened-nothing-installed once: fresh ubuntu:26.04 per candidate (current point release), full setup with no stage skipped, snapshot. The two smoke jobs then run in parallel from it.
- Every installed base is a copy of that snapshot plus its install; no base runs setup itself.
- No harness skips a setup stage: the skip and HARNESS_HARDENING_SKIP_STAGES are removed from lxd-backend.sh, ops/lxd-fleet/base.sh and vm-bootstrap.sh, and from 0-https-only-egress.

### Zoom in
Prototype 2026-10-31 (tmp/lxd-security-tools-proto.sh, tmp/lxd-security-tools-proto.log): a fresh LXD guest built like the gate bases, full setup with nothing skipped: 'Setup Complete!', exit 0; crowdsec and crowdsec-firewall-bouncer active, ufw active, nftables tables crowdsec/crowdsec6 loaded; lxc exec works, HTTPS to ghcr.io answers, docker works as statbus.
rc.06 smoke 41200539247: 'hardening start' twice (hardened-nothing-installed 95 s, installed-v2026.10.5-standalone-pre 92 s), both with --skip-stages security-tools.

### Closing review
Documentation: test/install-recovery/README.md describes the base layering (hardened once, copied). No memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An offline test shows an installed base is a copy of the hardened snapshot and runs no setup of its own (red before, green after)
- [ ] #2 An offline test shows the hardened base runs setup with no stage skipped, and no harness file passes --skip-stages, --only-stages or SKIP_STAGES to setup (red before, green after)
- [ ] #3 The smoke ramp job builds the hardened base before the two smoke jobs start; the rc gate log shows exactly one 'hardening start' per candidate, with every stage run, and the gate is green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-31 red (lib at 715a79038): test/install-recovery/tests/lxd-hardened-base-once-test.sh (fake LXD store, real lxd_base_for_candidate): hardened base runs setup with '--skip-stages security-tools'; the installed base is a fresh 'lxc launch ubuntu:26.04' that runs setup itself instead of copying hardened-nothing-installed/checkpoint; stage selections in lxd-backend.sh:540, vm-bootstrap.sh:953, ops/lxd-fleet/base.sh:55, 0-https-only-egress.sh:19. 4 FAIL, exit 1 (tmp/556-red.log).
<!-- SECTION:NOTES:END -->
