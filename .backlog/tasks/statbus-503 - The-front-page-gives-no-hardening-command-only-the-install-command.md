---
id: STATBUS-503
title: 'The front page gives no hardening command, only the install command'
status: Done
assignee: []
created_date: '2026-10-13 15:38'
updated_date: '2026-10-15 19:30'
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
### North Star
An administrator who reads only the README front page can harden the server and install StatBus on the stable channel, with no step left to discover from a script.

### Zoom out
The front page is where a new national office starts. It must give the whole path in order (harden, then install as the service account hardening creates), use the same release-matched commands as the deeper guides so it cannot drift from them, and recommend only the stable channel. Prerelease and canary channels are for StatBus staff and are not advertised there (owner ruling, 2026-10-13).

### Zoom in
- **Found, 2026-10-13:** the owner, reading the README, saw that it explained installing but not hardening, which was only discoverable inside the installer script, and that its pinned-version example used a release candidate (`--version v2026.03.0-rc.25`).
- **Done:** `39d244d9a` (2026-10-13). README "For Administrators" gives (1) harden the server in a root login shell with the release-matched `ops/setup-ubuntu-lts.sh` (never a master fetch), then (2) `curl -fsSL https://statbus.org/install.sh | bash`. The pinned example is `--version v2026.03.0`, and the section points at `doc/DEPLOYMENT.md` and the server-setup doc.
- **Proof:** read the README on master 2026-10-15; all four criteria hold. The mechanisms it describes (release-matched fetch, root-login-shell guard) are tested under STATBUS-488 and 492.

### Closing review
- **Memory:** none needed.
- **Documentation:** this ticket is the documentation change.
- **Cleanup:** none.
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

2026-10-15 vetting: README re-read on master; all four criteria hold. Nothing open, so Done.
<!-- SECTION:NOTES:END -->
