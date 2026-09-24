---
id: STATBUS-399
title: >-
  A box without public DNS installs with a private certificate: the installer
  offers it as the last choice, prints one command that installs trust on this
  Ubuntu box, and the plain-HTTP page lets browsers install the same trust
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
labels:
  - install
  - certificate
  - ubuntu
dependencies: []
priority: high
type: bug
ordinal: 352000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A standalone box with a private name can complete installation using an explicitly selected private certificate. The installer offers choices in this order: automatic certificate, the operator own certificate files, a certificate from Statistics Norway when available, and private certificate last.

For the private certificate choice, installation prints one command that installs trust on the Ubuntu box itself, using `sudo` when needed, so local terminal commands trust the site. The plain-HTTP page provides the same trust certificate and browser installation guidance.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

`caddy/templates/standalone.caddyfile.tmpl:145-155` supports automatic certificates or `TLS_CERT_FILE` and `TLS_KEY_FILE`; development uses `tls internal`. On the Finland laptop, the chosen name existed only in `/etc/hosts`. The certificate log reported NXDOMAIN through the staging authority and retried every 600 seconds. `curl` reached port 443 and received a TLS internal error.

The local Multipass experiment established the private-certificate path. With `tls internal`, `curl --cacert <root> https://statbus.statfin.eu/` completed full certificate verification and reached the application. PostgreSQL verification on port 5432 also succeeded when `sslmode=verify-full`, the root certificate, and `sslnegotiation=direct` were supplied; the default PostgreSQL negotiation did not pass through the existing TLS route. The generated root certificate was owned by root with mode 0600 inside 0700 directories, so the `statbus` user could not read it for the trust command. A later installer run regenerated the proxy configuration and restored automatic issuance, demonstrating that private-certificate selection must be represented by a configuration key rather than a generated-file edit. Source: `/Users/jhf/ssb/statbus/tmp/local-ville-replay.md`, lines 1023-1103.

Related: STATBUS-412 makes the certificate choice revisable on an installer rerun. This ticket supplies the private-certificate behavior itself.

Related delegated-certificate exit: STATBUS-358 proposes a StatBus-operated certificate service for boxes without public DNS. Its 2026-09-24 owner decision places registration, approval, identity, and challenge records in our Postgres database on niue. This ticket retains the private-certificate fallback when delegated issuance is unavailable.

## Proving scenario

Harness scenario `4-install-standalone-no-public-dns` chooses the final private-certificate option. Installation reaches green. The printed trust command makes `curl https://<name>/` succeed on the Ubuntu box, and the plain-HTTP page serves the same trust certificate for browser installation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The certificate choices appear in this order: automatic certificate, operator certificate files, certificate from Statistics Norway when available, and private certificate as the final explicit choice.
- [ ] #2 Selecting the private certificate completes standalone installation for a name resolved only inside the private network.
- [ ] #3 The installer prints one command that installs trust on the Ubuntu box itself, using elevated permission when required.
- [ ] #4 The plain-HTTP page serves the same trust certificate and browser installation guidance.
- [ ] #5 After the trust command runs, local terminal requests validate the private certificate and reach the site.
- [ ] #6 The private-certificate choice is stored in configuration and remains selected after configuration generation and installer reruns.
- [ ] #7 The trust command obtains the root certificate through a path readable by the operator account, and PostgreSQL guidance includes direct TLS negotiation for port 5432.
<!-- AC:END -->
