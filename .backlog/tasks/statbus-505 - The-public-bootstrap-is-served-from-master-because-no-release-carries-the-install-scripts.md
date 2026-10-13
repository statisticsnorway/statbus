---
id: STATBUS-505
title: >-
  The public bootstrap is served from master because no release carries the
  install scripts
status: To Do
assignee: []
created_date: '2026-10-13 15:39'
labels:
  - release
  - docs
  - cloud
dependencies: []
priority: medium
type: bug
ordinal: 431204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 by the owner hint (the Caddyfile on niue). statbus.org is routed by Caddy on niue, and its block reads: handle /install.sh redirects 302 to https://raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/install.sh; handle /uninstall.sh does the same for uninstall.sh. So the bootstrap every operator runs is the MASTER branch, which is the same shape as STATBUS-488 (a prepare script from master) and the last place that bypasses the rule that only a named release candidate reaches an installation.

WHY IT IS LIKE THAT, grounded: a release publishes only sb binaries, checksums.txt and release-manifest.json (cli/internal/release/check.go requiredAssets), and .github/workflows/release.yaml uploads no scripts. There is therefore no tagged install.sh for the redirect to point at, and releases/latest/download/install.sh would 404.

OPTIONS: (A) keep master deliberately, recorded as THE one documented bootstrap exception; (B) publish install.sh, uninstall.sh and the prepare script as release assets and point the redirects at releases/latest/download/, so the bootstrap is the tagged artifact and statbus.org/setup.sh can exist as the one-command prepare the owner asked for (STATBUS-504); (C) serve a small resolving snippet from the domain. Coordinator recommendation: B, and it is the owner decision because it changes the release workflow and a production Caddyfile on niue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The decision is recorded: either the bootstrap exception is documented as deliberate, or the scripts become release assets and the redirects move to the tagged artifact.
- [ ] #2 If the scripts become release assets: a release carries them, the redirect targets are updated on niue, and fetching statbus.org/install.sh can no longer serve code from a branch. Checked by the asset list of a real release and by the redirect target.
- [ ] #3 Whether or not this changes, STATBUS-504 answer records how preparation becomes one command, consistently with STATBUS-488 release matching.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-13. The Caddyfile on niue is outside this repository (caddy/templates only renders slot deployments), so any change there is a production edit requiring the owner go and a caddy reload.
<!-- SECTION:NOTES:END -->
