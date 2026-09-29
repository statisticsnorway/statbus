---
id: STATBUS-429
title: >-
  The certificate remedy works for the install user: caddy/data/custom-certs is
  writable without sudo
status: To Do
assignee: []
created_date: '2026-09-29 08:24'
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
