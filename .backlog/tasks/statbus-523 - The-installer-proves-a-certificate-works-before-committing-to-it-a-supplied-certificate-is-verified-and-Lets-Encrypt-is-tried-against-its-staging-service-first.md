---
id: STATBUS-523
title: >-
  The installer proves a certificate works before committing to it: a supplied
  certificate is verified, and Let's Encrypt is tried against its staging
  service first
status: To Do
assignee: []
created_date: '2026-10-20 21:21'
updated_date: '2026-10-20 21:22'
labels: []
dependencies:
  - STATBUS-399
type: feature
ordinal: 449204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Choosing HTTPS never locks an operator out or leaves them guessing: install proves the certificate works before committing to it, and says plainly what failed when it does not.

### Zoom out
Owner direction, 2026-10-20.
- **Supplied certificate:** install verifies it before serving with it.
- **Let's Encrypt:** install first runs Caddy against Let's Encrypt's staging service, whose rate limits cannot lock out the real domain. Only when staging issues a certificate does it switch to production. If staging fails, the operator sees why.
- **Related tickets:**
  - STATBUS-394 checks the advertised site at the end of install.
  - STATBUS-389 decided there is no outside reachability probe; StatBus has no outside service.
  - STATBUS-399 covers private certificates for names without public DNS.

### Zoom in
- **Where the choice lives:** `caddy/templates/standalone.caddyfile.tmpl` picks either `tls <cert> <key>` (TLS_CERT_FILE/TLS_KEY_FILE, placed by `./sb cert install`) or `tls { issuer acme }`. `cli/internal/config/config.go` `validateTLSPaths` checks only paths today.
- **Staging:** Let's Encrypt's staging directory is `https://acme-staging-v02.api.letsencrypt.org/directory`. Caddy takes it as `issuer acme { dir ... }`, and its ACME log states why an issue failed.

### Closing review
- **Memory:** none expected.
- **Documentation:** `doc/DEPLOYMENT.md` certificate section describes the staging-first behaviour and the choice after a failure.
- **Cleanup:** none expected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A supplied certificate that does not match its key, does not cover the chosen name, is outside its validity dates or does not chain to a trusted root stops install before services start, naming which of these failed
- [ ] #2 Choosing Let's Encrypt first obtains a staging certificate for the chosen name. Only then does install switch to production
- [ ] #3 A real box proves both paths: a supplied certificate accepted and a bad one refused, and a Let's Encrypt staging failure reported (an LXD guest without public DNS)
- [ ] #4 A staging failure shows the operator Caddy's ACME reason in plain words and then does what the owner decision (the [Owner] criterion) records. Production is never tried before staging succeeds unless that decision allows it
- [ ] #5 [Owner] Decide what follows a staging failure, interactive and unattended, and record it in Implementation Notes. Options: (a) stop, so the operator picks another certificate option and reruns; (b) offer to go back to the certificate question or continue on production anyway; (c) continue on HTTP only and print how to retry. The chosen option becomes the behaviour the staging-failure criterion asserts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Owner 2026-10-20: deferred to the STATBUS-399 discussion
STATBUS-399 holds the HTTP-first setup (install completes on plain HTTP, the redirect to HTTPS only once a certificate works). The staging-first Let's Encrypt and supplied-certificate checks are decided together with it, not now. Only in-progress tickets are being worked.
<!-- SECTION:NOTES:END -->
