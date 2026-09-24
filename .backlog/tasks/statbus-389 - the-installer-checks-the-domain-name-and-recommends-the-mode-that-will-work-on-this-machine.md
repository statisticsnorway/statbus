---
id: STATBUS-389
title: The installer checks the domain name and recommends a workable certificate choice
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - release-bug
  - install
dependencies:
  - STATBUS-358
  - STATBUS-399
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**In Progress.** `0a166d25e`, `373d15fc3`: `cli/cmd/install_domain.go` and `install_domain_test.go` separate public DNS observation from reachability (#1 partly). `4-install-standalone-no-public-dns.sh` is authored, but #2-3 require the unshipped private-certificate choice (399) and real-VM proof. **Remaining:** deliver that choice and verify HTTPS plus honest certificate advice on a private-name VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the domain answer, the installer checks public DNS and proposes an external reachability check. It explains the observed result and recommends a certificate choice that can complete installation on the current machine. Delegated certificates are coordinated with STATBUS-358 and private certificates with STATBUS-399.

## Evidence, 2026-09-24

The Finland domain returned NXDOMAIN and automatic certificate issuance retried (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:6-12`). Current standalone configuration requests automatic public certificates (`caddy/templates/standalone.caddyfile.tmpl:145-155` at master `7a9cf707e`). External reachability checking is proposed behavior because DNS alone does not establish reachability.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_domain_test.go::TestDomainAssessmentSeparatesDNSFromReachability` reports public DNS as an observation and labels external reachability as checked only when that proposed probe actually ran.
- [ ] #2 `new: test/install-recovery/scenarios/4-install-standalone-no-public-dns.sh` uses a name absent from public DNS, selects the offered private-certificate fallback from STATBUS-399, and completes installation to a working HTTPS page.
- [ ] #3 `new: test/install-recovery/scenarios/4-install-standalone-no-public-dns.sh` records that automatic public certificates were not promised and that the recommended choice was workable on the installed machine.
<!-- AC:END -->
