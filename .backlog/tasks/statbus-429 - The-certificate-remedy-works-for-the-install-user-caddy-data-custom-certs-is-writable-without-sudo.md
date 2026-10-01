---
id: STATBUS-429
title: >-
  The certificate remedy works for the install user: caddy/data/custom-certs is
  writable without sudo
status: In Progress
assignee: []
created_date: '2026-09-29 08:24'
updated_date: '2026-10-01 10:29'
labels:
  - install
dependencies: []
priority: high
ordinal: 378200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the Ville replay (tmp/ville-replay-v2026.09.3.md D3, 2026-09-29). Once the proxy has started, Docker creates caddy/data/ as root:root 755 (bind mount ./data of caddy/docker-compose.yml; observed on LXD forks ville-r1b and ville-r2). The v2026.09.3 certificate refusal (cli/internal/config/config.go validateTLSPaths guidance, INSTALL_FIX in cli/cmd/install_failure_cause.go and install.sh:841) and doc/DEPLOYMENT.md Custom TLS Certificates tell the operator to put files in ~/statbus/caddy/data/custom-certs/, which then fails with Permission denied for the statbus user. Every box that fixes a certificate after its first install hits it (Ville's exact case). Fix in the product: the install user owns caddy/data/custom-certs/ on new installs (created before the first compose up) and on existing boxes (repaired as a step, like Backup ownership), so the printed remedy works as written.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fresh install creates caddy/data/custom-certs/ owned by the install user before any container starts
- [ ] #2 An existing box whose caddy/data/ is root-owned gets caddy/data/custom-certs/ repaired to the install user by the installer, without sudo
- [ ] #3 A scenario on a box that has run Services follows the printed certificate remedy as the statbus user and reaches a ready installation
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Replay 2026-09-29 (tmp/ville-cert-install-replay.md, LXD forks ville-c1/c2 of Ville's exact broken v2026.09.2 state): ./sb cert install itself fails on the root-owned caddy/data (mkdir custom-certs: permission denied, cert.go writeCertAndKey), on both v2026.09.2 and v2026.09.3 binaries, with no guidance (D5). After a one-time ownership fix it works end to end (files, .env.config, config, proxy restart, SHA-256 probe via /etc/hosts), and the stable installer then completes 17/17 with HTTPS 200. Cert-first (before upgrading) is the shortest path: one installer pass, no step-6 refusal. Fix under review on fix/429-custom-certs (063498e52): cert install repairs custom-certs itself; remedies name ./sb cert install.

Merged 2026-09-29: merge 8579e6e61 (+ lint fix a0ee1f2ed; Go Test 36569376957 success, Harness Selftest success). Direction per owner: operators fix certificates with ./sb cert install, never manual copying. What shipped to master: ./sb cert install repairs a root-owned or unwritable caddy/data/custom-certs itself through a container (the box's proxy image, alpine:3.20 fallback, no network), probes writability after; a failed repair prints the reason, the one sudo line, the rerun, then detail. Every certificate remedy (install_failure_cause.go, install.sh allowlists, validateTLSPaths guidance, doc/DEPLOYMENT.md incl. renewal and cert remove) names cd ~/statbus && ./sb cert install. Reviews: tmp/review-429.md, -2.md, -3.md (MERGE). Scenario 5-install-cert-repair-via-cert-install is HARNESS_SKIP_DEFAULT until its first green explicit LXD run. ACs #1/#2 still describe the superseded installer-step plan: owner to approve rewording to the cert install direction. AC#3 needs the explicit LXD run at the next candidate. Open non-blocking: R-i first half, R-j (cert install --help examples), R-f, README on-demand note.
2026-10-01 10:29 UTC, factual reconciliation: `8579e6e61` and `a0ee1f2ed` are ancestors of published master `4eba1149e`, the source prepared for the first candidate. They are not in stable `v2026.09.3`. Status is In Progress, not Done. AC#3 needs an explicit non-default run of `5-install-cert-repair-via-cert-install` against the built candidate. AC#1/#2 retain their current wording and remain unchecked until the owner decides whether to reword them to the merged `./sb cert install` design.
<!-- SECTION:NOTES:END -->
