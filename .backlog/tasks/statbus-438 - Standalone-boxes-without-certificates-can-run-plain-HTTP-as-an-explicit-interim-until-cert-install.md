---
id: STATBUS-438
title: >-
  Standalone boxes without certificates can run plain HTTP as an explicit
  interim until cert install
status: To Do
assignee: []
created_date: '2026-10-01 13:20'
labels:
  - install
dependencies: []
priority: medium
ordinal: 386200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Raised by the owner during the STATBUS-429 judgment (2026-10-01 13:17 UTC): if you have no certificates you should be able to get going without HTTPS, plain HTTP until you can install the certificates.

Current coverage: standalone mode always serves HTTPS via automatic Let's Encrypt (needs public DNS and ACME reachability); private mode is HTTP behind a host-level proxy by design. A standalone box on an internal network without ACME reachability AND without custom certificates has no supported interim state today.

Deliberately NOT part of STATBUS-429 (the unified certificate mechanism). This ticket is the interim HTTP capability that lets such a box run before its certificates arrive.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A standalone box on an internal network without ACME reachability and without custom certificates can be installed serving plain HTTP, with the mode recorded explicitly in .env.config (not inferred)
- [ ] #2 Every such box's docs and remedies name ./sb cert install as the path to HTTPS, and installing a certificate transitions the box from HTTP to HTTPS without reinstall
- [ ] #3 The mode is refused or warns loudly when SITE_DOMAIN is publicly routable, so it cannot silently weaken a public box
- [ ] #4 An explicit LXD guest run proves both the HTTP-only install and the cert-install transition to HTTPS
<!-- AC:END -->
