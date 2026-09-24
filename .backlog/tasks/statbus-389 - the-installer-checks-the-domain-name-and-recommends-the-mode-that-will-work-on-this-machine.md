---
id: STATBUS-389
title: >-
  The installer checks the domain name and recommends the mode that will work on
  this machine
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 15:35'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the domain question, the installer checks public DNS and whether this computer is reachable for automatic certificate setup. It then explains the result in one sentence and offers the certificate choices that work, in best-to-fallback order.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

The Finland laptop used `statbus.statfin.eu` only in `/etc/hosts` and had a private home-network address. The certificate service reported NXDOMAIN, retried every 600 seconds, and HTTPS returned a TLS internal error.

## Proving scenario

New harness scenario `4-install-standalone-no-public-dns`: choose standalone with a name absent from public DNS. Assert that the installer explains why automatic setup is unavailable and offers, in order, the operator own certificate files, a certificate from Statistics Norway when available, and a private certificate as the final explicit choice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The installer checks public DNS and external reachability after the domain answer.
- [ ] #2 The installer states whether automatic certificate setup works for this computer.
- [ ] #3 When automatic setup is unavailable, the installer offers the working certificate choices in the agreed order.
<!-- AC:END -->
