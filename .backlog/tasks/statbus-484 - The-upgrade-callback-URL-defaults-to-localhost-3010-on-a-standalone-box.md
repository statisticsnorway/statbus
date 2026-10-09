---
id: STATBUS-484
title: 'The upgrade callback URL defaults to localhost:3010 on a standalone box'
status: To Do
assignee: []
created_date: '2026-10-09 07:20'
labels: []
dependencies: []
ordinal: 410204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND during STATBUS-474's first real install run (a fresh local guest, 2026-10-08). cli/internal/installinput/config.go:471 defaults the value to 'http://localhost:3010' regardless of deployment mode or domain, while BROWSER_REST_URL is derived from the domain. Its only reader in cli/ is the upgrade callback path (service.go:12383), which passes it as STATBUS_URL to UPGRADE_CALLBACK - e.g. ops/notify-slack.sh prints 'Instance: <url>'. So a standalone box with an upgrade callback configured announces itself as localhost:3010, which is both wrong and unactionable for whoever reads the notification. NORTH STAR: the callback reports the instance's real external URL, derived the same way every other external address is, in every deployment mode.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The value the upgrade callback reports is derived from the configured domain, not a hardcoded localhost:3010, in standalone and private modes
- [ ] #2 The local development mode keeps a working default
- [ ] #3 A test pins the derivation for standalone, private and development
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The observed wrong value and the corrected one are recorded in the ticket
<!-- DOD:END -->
