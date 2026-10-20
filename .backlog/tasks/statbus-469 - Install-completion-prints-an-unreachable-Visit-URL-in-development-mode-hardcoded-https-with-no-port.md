---
id: STATBUS-469
title: >-
  Install completion prints an unreachable Visit URL in development mode:
  hardcoded https:// with no port
status: In Progress
assignee: []
created_date: '2026-10-08 12:15'
updated_date: '2026-10-20 20:45'
labels:
  - installer
  - devx
dependencies: []
priority: medium
type: bug
ordinal: 395204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the completion banner prints the origin the installation actually serves. It never prints a URL the install cannot answer on.

ZOOM OUT. Printed origins are derived from the same generated settings the services bind to (mode and effective ports), never assembled from a hardcoded scheme. Then the banner can only name what the box actually serves.

THE DEFECT (field log 2026-10-08). The banner printed 'Visit: https://local.statbus.org' and the operator got 'unable to connect'. That install is in DEVELOPMENT mode, where the web entry serves plain HTTP on 3010 and TLS on 3011, so port 443 has no listener. The URL is also wrong to be TLS-only there, since both origins exist.

THE MECHANISM. `cli/cmd/install.go` (line 1364 on master `cb34436b4`) load .env.config, read SITE_DOMAIN, and print 'Visit: https://%s' with a hardcoded scheme and no port. The ports the installation actually binds are generated configuration: CADDY_HTTP_PORT and CADDY_HTTPS_PORT (cli/internal/config/config.go lines 811-812), derived from DEPLOYMENT_SLOT_PORT_OFFSET (config.go lines 424 and 617). So in development the banner names port 443 while the services listen elsewhere; in standalone (80 and 443) the portless URL happens to be right; in private mode the box sits behind a host-level proxy, so the external origin is portless again even though the local listeners are slot ports.

CLOSING REVIEW. Memory: none needed. Documentation: none needed; the banner is the operator text. Cleanup: none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The completion banner derives its origin from the mode and the effective configured ports, not from a hardcoded scheme and port.
- [x] #2 A development-mode install prints a reachable origin including the port, and prints both the TLS and the plain-HTTP origin so the operator has a working link either way.
- [x] #3 A standalone install keeps the portless https://<domain>.
- [x] #4 A private-mode install names the external origin as reached through the host proxy, portless, and never presents a slot port as the public URL.
- [x] #5 Tests cover at least development and standalone and assert the printed origin per mode.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The observed banner for a development install and for a standalone install is recorded in the ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner report 2026-10-08: are we really bound to that, or should we show the port we are bound to? Answer: show the bound port; the install serves 3010/3011 in development mode, so the portless TLS URL is unreachable. Related: STATBUS-465 removes the battery-driven development default that put this field install in development mode at all.

2026-10-15 vetting: not implemented. cli/cmd/install.go still prints `Visit: https://%s` from SITE_DOMAIN with no port or mode (line 1364 on master cb34436b4). No commit references this ticket besides its filing (bfbeea61e). Status set to To Do: the description is already clear and owner-shaped, and nobody is working on it.

### Fix (4baa85852, 2026-10-17)
- `installVisitOrigins` (cli/cmd/install.go) reads the generated .env: SITE_DOMAIN, CADDY_DEPLOYMENT_MODE, CADDY_HTTP_PORT, CADDY_HTTPS_PORT. Development prints `http://<domain>:<http port>` and `https://<domain>:<https port>`. Standalone and private print `https://<domain>`.
- **Red, then green:** `TestInstallVisitOriginsFollowModeAndPorts_STATBUS469` ran against the old rule (extracted unchanged), which gave the Finland link `https://local.statbus.org` for development, so it failed. The standalone and private cases already matched. With the fix all three pass. The cmd package passes; golangci-lint reports 0 issues.
- **Real values:** this machine's development .env has ports 3010/3011, and both origins answer (307 to login). dev and demo are private, with SITE_DOMAIN dev/demo.statbus.org, and their public HTTPS answers through the host proxy.

### Observed banners (2026-10-20)
- **Development:** the shipped installVisitOrigins (v2026.10.3) run against this machine's real development .env prints 'Visit: http://local.statbus.org:3010' and 'Visit: https://local.statbus.org:3011'. Both answer (HTTP 307 to login).
- **Standalone:** the next candidate's clean LXD install (0-happy-install, standalone mode) prints the banner from the new code. The rc.01 fleet's 'Visit: https://statbus-test.local' lines came from the old v2026.09.2 baseline install inside the arcs, so they do not prove the new code. Recorded at the next candidate.
<!-- SECTION:NOTES:END -->
