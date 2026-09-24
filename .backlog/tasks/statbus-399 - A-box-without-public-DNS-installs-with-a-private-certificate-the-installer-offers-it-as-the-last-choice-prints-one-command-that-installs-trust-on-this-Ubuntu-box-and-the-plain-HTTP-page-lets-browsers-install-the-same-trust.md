---
id: STATBUS-399
title: A private-name installation offers a private certificate and complete trust setup
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:42'
labels:
  - install
  - certificate
  - ubuntu
dependencies:
  - STATBUS-389
priority: high
type: bug
ordinal: 352000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A standalone box with a private name can select a private certificate as the final certificate choice. The installer persists that choice, completes installation, exposes only the public root certificate to the operator, prints one pasteable Ubuntu trust command using `sudo`, and serves the same authority certificate with browser trust guidance from the plain-HTTP entry point. PostgreSQL guidance uses direct TLS negotiation.

## Evidence, 2026-09-24

Current standalone configuration supports automatic certificates or supplied certificate files (`caddy/templates/standalone.caddyfile.tmpl:145-155` at master `7a9cf707e`), while development mode uses an internal authority (`caddy/templates/development.caddyfile.tmpl:198-202` at master `7a9cf707e`). Finland automatic issuance failed with NXDOMAIN and retries (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:6-12`). The local hand-edited experiment proved trusted HTTPS and PostgreSQL direct TLS, but also found the generated root unreadable by the operator and the choice lost on regeneration (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:1023-1103`). That experiment is evidence, not shipped capability.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_certificate_choice_test.go::TestPrivateCertificateIsFinalChoice` shows automatic, your own certificate, Statistics Norway certificate when available, then private certificate.
- [ ] #2 `new: test/install-recovery/scenarios/4-install-standalone-no-public-dns.sh` selects private certificate for a private-only name and completes installation.
- [ ] #3 `new: test/install-recovery/scenarios/4-private-certificate-sudo-trust.sh` pastes the printed `sudo` command on pristine Ubuntu, with no preinstalled key, and verifies the site authority.
- [ ] #4 `new: test/install-recovery/scenarios/4-private-certificate-root-only.sh` proves the operator-readable artifact contains the public root certificate and no private key.
- [ ] #5 `new: test/install-recovery/scenarios/4-private-certificate-browser-trust.sh` downloads the same CA from the plain-HTTP entry point and verifies browser authority trust, not merely certificate equality.
- [ ] #6 `new: cli/cmd/install_certificate_choice_test.go::TestPrivateChoicePersistsAcrossGenerationAndRerun` proves the choice survives settings generation and installer rerun.
- [ ] #7 `new: test/install-recovery/scenarios/4-private-certificate-postgres-direct-tls.sh` verifies PostgreSQL with `sslmode=verify-full`, the served root, SNI, and direct TLS negotiation.
<!-- AC:END -->
