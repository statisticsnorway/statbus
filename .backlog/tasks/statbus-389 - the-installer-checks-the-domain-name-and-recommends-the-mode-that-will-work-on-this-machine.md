---
id: STATBUS-389
title: >-
  The installer tells the operator whether an automatic certificate can work for
  the chosen domain
status: Done
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-10-20 21:17'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
While answering the domain question, the operator learns whether an automatic public certificate can work on this machine, and what to choose instead when it cannot.

### Zoom out
An automatic public certificate needs two things the installer cannot assume: the name must be in public DNS, and the certificate authority must reach this machine from outside. The installer reports only what it actually observed. Finding the name in DNS is not proof of reachability, so the advice never promises a certificate on DNS alone. When the name is absent, the advice points to a choice that will work today rather than letting the web entry point retry for days.

Which alternative certificate the operator then gets is not this ticket: private certificates are STATBUS-399, Statistics Norway-issued certificates are STATBUS-358.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** standalone mode with `statbus.statfin.eu`, which had no public DNS record. Caddy's ACME challenge failed with `NXDOMAIN` and retried every 600 s for up to 30 days (`tmp/finland-answers-4.txt:1-12`). Nothing told the operator before installation that this could not work.
- **Shipped (v2026.09.3):** `bda0df07b`, `0a166d25e`, `0c467a019`. `cli/cmd/install_domain.go` queries a public resolver directly (not `/etc/hosts`) right after the domain answer and prints one of two sentences: absent from public DNS, so no automatic certificate can be promised and local development is recommended; or present in DNS, but port 80 from outside was not checked, so the certificate is not yet confirmed.
- **Proof:** `TestDomainAssessmentSeparatesDNSFromReachability` (Go Test). Scenario `test/install-recovery/scenarios/4-install-standalone-no-public-dns.sh` PASS in rc.17 LXD: absence detected, automatic certificate not promised.
- **Not built:** an outside reachability probe (port 80 tested from the internet). The installer says honestly that it did not check.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the installer's own sentence is the operator documentation.
- **Cleanup:** the two former criteria about completing a private-certificate install duplicated STATBUS-399 AC2 and were removed here; the 389 <-> 399 dependency cycle was removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Public DNS is reported as an observation, separate from reachability, and reachability is never claimed unless checked (`TestDomainAssessmentSeparatesDNSFromReachability`)
- [x] #2 On a real box with a name absent from public DNS, the installer says an automatic certificate cannot be promised and recommends a workable choice (`4-install-standalone-no-public-dns.sh`, rc.17 LXD PASS)
- [x] #3 [Owner] Decide whether an outside reachability probe (port 80 tested from the internet) is wanted, and record it in Implementation Notes. No: check this and set Done. Yes: add the probe as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** green in Go Test `36503468493` (v2026.09.3).
- **AC2:** rc.17 LXD scenario PASS, recorded in the 2026-09-29 audit (`ea170989e`).
- **AC3:** open.

### Owner decision 2026-10-20: no outside reachability probe
StatBus has no external service to probe from. The installer checks what it can see locally (public DNS, the port free, STATBUS-521) and says plainly when an automatic certificate cannot be promised. Operators who enable Let's Encrypt take responsibility for reachability. Caddy's own certificate logs show what happens. Any later work is a new ticket.
<!-- SECTION:NOTES:END -->
