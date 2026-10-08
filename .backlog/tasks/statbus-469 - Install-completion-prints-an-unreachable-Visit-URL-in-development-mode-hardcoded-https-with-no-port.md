---
id: STATBUS-469
title: >-
  Install completion prints an unreachable Visit URL in development mode:
  hardcoded https:// with no port
status: In Progress
assignee: []
created_date: '2026-10-08 12:15'
updated_date: '2026-10-08 12:15'
labels:
  - installer
  - devx
dependencies: []
priority: medium
ordinal: 395204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the completion banner prints the origin the installation actually serves. It never prints a URL the install cannot answer on.

THE DEFECT (field log 2026-10-08). The banner printed 'Visit: https://local.statbus.org' and the operator got 'unable to connect'. That install is in DEVELOPMENT mode, where the web entry serves plain HTTP on 3010 and TLS on 3011, so port 443 has no listener. The URL is also wrong to be TLS-only there, since both origins exist.

THE MECHANISM. cli/cmd/install.go lines 1323-1327 load .env.config, read SITE_DOMAIN, and print 'Visit: https://%s' with a hardcoded scheme and no port. The ports the installation actually binds are generated configuration: CADDY_HTTP_PORT and CADDY_HTTPS_PORT (cli/internal/config/config.go lines 811-812), derived from DEPLOYMENT_SLOT_PORT_OFFSET (config.go lines 424 and 617). So in development the banner names port 443 while the services listen elsewhere; in standalone (80 and 443) the portless URL happens to be right; in private mode the box sits behind a host-level proxy, so the external origin is portless again even though the local listeners are slot ports.

REQUIRED BEHAVIOUR.
1. Derive the printed origin from the mode and the effective ports, from the same source the services use, not hardcoded.
2. Development mode prints a reachable origin including the port, and prints BOTH so the operator has a working link whatever they clicked: the TLS origin (for example https://local.statbus.org:3011) and the plain-HTTP origin (for example http://local.statbus.org:3010).
3. Standalone keeps the portless https://<domain>.
4. Private mode names the external origin as people reach it through the host proxy, portless, and does not present a slot port as the public URL.
5. The banner never prints an origin the installation cannot serve.

TESTS: at least development and standalone, asserting the printed origin per mode, including the port in development and its absence in standalone.

EVIDENCE TO RECORD: the observed banner for a development install and for a standalone install.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The completion banner derives its origin from the mode and the effective configured ports, not from a hardcoded scheme and port.
- [ ] #2 A development-mode install prints a reachable origin including the port, and prints both the TLS and the plain-HTTP origin so the operator has a working link either way.
- [ ] #3 A standalone install keeps the portless https://<domain>.
- [ ] #4 A private-mode install names the external origin as reached through the host proxy, portless, and never presents a slot port as the public URL.
- [ ] #5 Tests cover at least development and standalone and assert the printed origin per mode.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The observed banner for a development install and for a standalone install is recorded in the ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner report 2026-10-08: are we really bound to that, or should we show the port we are bound to? Answer: show the bound port; the install serves 3010/3011 in development mode, so the portless TLS URL is unreachable. Related: STATBUS-465 removes the battery-driven development default that put this field install in development mode at all.
<!-- SECTION:NOTES:END -->
