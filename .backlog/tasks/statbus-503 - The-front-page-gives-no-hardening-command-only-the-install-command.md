---
id: STATBUS-503
title: 'The front page gives no hardening command, only the install command'
status: In Progress
assignee: []
created_date: '2026-10-13 15:38'
updated_date: '2026-10-13 15:38'
labels:
  - docs
  - install
dependencies: []
priority: medium
type: enhancement
ordinal: 429204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 by the owner reading the main README: it tells an administrator how to install StatBus but never how to harden the Ubuntu server first, so the hardening step is discoverable only by reading the installer script. The README administrator section also offered its pinned-version example with a release candidate (--version v2026.03.0-rc.25), which nudges an ordinary operator toward a prerelease; the owner ruling of 2026-10-13 is that the general guidance stays on the stable channel and does not advertise our internal channels.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The README administrator quick start gives BOTH commands, in order: harden the server, then install StatBus as the service account hardening created. Checked by reading the README.
- [x] #2 The prepare command shown is the release-matched one (the setup script of the release being installed, never a master fetch) and states that it runs in a root login shell. Checked by reading the README.
- [x] #3 The pinned-version example uses a stable tag, and no prerelease or canary channel is recommended on the front page. Checked by reading the README.
- [x] #4 The section points at the deployment guide and the server-setup doc for detail rather than duplicating them. Checked by reading the README.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed and done 2026-10-13 by the coordinator, docs-only. No test accompanies it, deliberately: it changes prose, not behaviour, and the mechanism it describes (the release-matched fetch, the root-login-shell guard) is already pinned by the STATBUS-488 and STATBUS-492 tests. The commands in the README are the same ones doc/setup-ubuntu-lts.md and doc/DEPLOYMENT.md carry, so the front page cannot drift from the guides without a reader noticing.
<!-- SECTION:NOTES:END -->
