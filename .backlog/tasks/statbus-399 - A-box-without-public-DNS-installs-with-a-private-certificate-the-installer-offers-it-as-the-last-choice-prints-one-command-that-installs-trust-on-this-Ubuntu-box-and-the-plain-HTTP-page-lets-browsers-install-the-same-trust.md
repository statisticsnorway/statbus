---
id: STATBUS-399
title: A private-name installation offers a private certificate and complete trust setup
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-25 13:53'
labels:
  - owner-decision
  - install
  - certificate
  - ubuntu
dependencies:
  - STATBUS-389
priority: high
type: bug
ordinal: 352000
---

## Status 2026-09-24

**To Do, owner decision.** #1-7 not met: no persisted standalone private-certificate choice; `4-install-standalone-no-public-dns.sh` is only an authored scenario and currently cannot establish #2. **Remaining:** choose the certificate/trust policy, then ship the last-choice selector, public-root-only trust command and HTTP browser trust page, persistence, and full HTTPS/PostgreSQL direct-TLS VM proofs.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A standalone box with a private name can select a private certificate as the final certificate choice. The installer persists that choice, completes installation, exposes only the public root certificate to the operator, prints one pasteable Ubuntu trust command using `sudo`, and serves the same authority certificate with browser trust guidance from the plain-HTTP entry point. PostgreSQL guidance uses direct TLS negotiation.

## Evidence, 2026-09-24

Current standalone configuration supports automatic certificates or supplied certificate files (`caddy/templates/standalone.caddyfile.tmpl:145-155` at master `7a9cf707e`), while development mode uses an internal authority (`caddy/templates/development.caddyfile.tmpl:198-202` at master `7a9cf707e`). Finland automatic issuance failed with NXDOMAIN and retries (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:6-12`). The local hand-edited experiment proved trusted HTTPS and PostgreSQL direct TLS, but also found the generated root unreadable by the operator and the choice lost on regeneration (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:1023-1103`). That experiment is evidence, not shipped capability.
## Owner decisions, 2026-09-25 13:43Z

- **Ship this first.** It is Finland's unblocker; STATBUS-358 (the SSB certificate service) proceeds concurrently but separately.
- In the installed flow the private certificate also serves as the *temporary* certificate while an SSB-issued certificate awaits approval; swapping to the SSB-issued certificate later is a config change, not a reinstall.

## Owner decisions, 2026-09-25 13:52Z — flow shape

- **No blocking/locking wait in the installer.** Waiting for approval must not hold the installer open: unfriendly for scripting. Instead the installer STOPS and presents the choice.
- **Interactive:** the operator chooses at the prompt.
- **Non-interactive:** the installer prints exact instructions: which environment variables to set to select each path, and exactly what to report to Statistics Norway.
- Private-certificate-as-temporary with a later swap to the SSB-issued certificate is the accepted way to get a box running immediately.

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
