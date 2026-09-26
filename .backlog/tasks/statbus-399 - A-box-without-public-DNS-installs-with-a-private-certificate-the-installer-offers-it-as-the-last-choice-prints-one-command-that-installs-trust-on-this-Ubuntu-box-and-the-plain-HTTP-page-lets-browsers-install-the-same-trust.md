---
id: STATBUS-399
title: A private-name installation offers a private certificate and complete trust setup
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-26 09:12'
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

## Owner design direction, 2026-09-26 08:17Z — HTTP-first install

A standalone box without a certificate must NOT be unusable (today: port 80 redirects to a dead HTTPS, standalone.caddyfile.tmpl:57-58). Instead:

1. **Install completes HTTP-only.** No certificate at install time → the box boots and serves plain HTTP.
2. **A persistent certificate-warning interstitial:** every front-page access lands on a "you are not running secure — fix your certificate" page with the exact instructions (bring your own / we provide / private CA per the 399 choice order), not the front page. The operator can click through and use the system, but the interstitial returns on every front-page access until TLS is fixed.
3. **The plain-HTTP entry also serves the trust material** (this ticket's existing browser-trust design composes with the interstitial).
4. **Self-generating a private certificate requires a deliberate opt-in gesture** (explicit checkbox/confirmation), never a default.
5. Open sub-question (owner raised): restrict to localhost/LAN while uncertified, or open with the warning? Coordinator note for that discussion: HTTP logins expose credentials to the LAN — the interstitial handles awareness, not sniffing.

Consequence for the harness (418): the install.sh cert-staging seam (STATBUS_HARNESS_CERT_STAGING) can retire once HTTP-first exists — the harness installs HTTP-first, asserts the interstitial, then provisions a certificate through the documented operator path and asserts HTTPS. No faking, no harness-only seams.

## Owner design rulings, 2026-09-26 08:46Z

- **Open with the persistent warning** (not localhost-restricted). Rationale: real-world installers do not have certificates figured out at install time; they must be able to install, start, and be guided persistently toward a secure, proper installation.
- **No permanent redirect and no HSTS while uncertified.** Browsers cache 301s and HSTS — either would keep sending users to a dead HTTPS even after the certificate is fixed. The HTTP→HTTPS redirect must be CONDITIONAL on a certificate actually being configured (today the standalone template redirects unconditionally, caddy/templates/standalone.caddyfile.tmpl:57-58 — that changes).
- **PostgreSQL TLS:** by design PostgreSQL connections go through Caddy's L4 proxy, which requires a certificate — so direct DB connections stay encryption-required by default. Relaxing that for known-safe local environments is allowed to be considered, but the default posture is: fix the certificate first.
- LXD-as-default is the owner's stated priority for delivery speed; the 3-hour-per-change VM cycle is the pain this removes.

## Owner design rulings, 2026-09-26 09:09Z — expiry is the real hazard (Alabama... Albania runs an expired certificate TODAY)

Certificate expiry, not just absence, must degrade gracefully. Real-world case: Albania is running HTTPS with an expired certificate right now because they could not install the new one.

1. **No HSTS in principle** — it caches in browsers for effectively forever; if the certificate later expires, pinned browsers refuse HTTP and users can never reach the guidance page. If HSTS is ever used at all, its max-age must be well below the certificate's remaining lifetime — the simple rule is: don't.
2. **Redirects are temporary only** (302), never permanent (301), for the same cache-poisoning reason.
3. **Certificate presence AND validity drive the redirect:** uncertified OR expired → serve HTTP with the persistent interstitial/guidance; certified and valid → HTTPS with a temporary redirect. The transition both ways must be automatic (no operator shelling in to fix Caddy while users are locked out).
4. **The certificate lives in the database with its expiry recorded.** The DB record is the system's knowledge of certificate state: the app warns ahead of expiry (escalating interstitial even while HTTPS still works), the upgrade/install flow can surface it, and the expiry transition triggers the degrade-to-HTTP regeneration. (Caddy still reads files; the DB is the decision record, a sync keeps them in agreement.)
5. **PostgreSQL over Caddy's L4 proxy requires the certificate** — on expiry that path breaks too. Default posture stands (fix the certificate first); a deliberate relaxation for known-safe local environments may be considered.

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
