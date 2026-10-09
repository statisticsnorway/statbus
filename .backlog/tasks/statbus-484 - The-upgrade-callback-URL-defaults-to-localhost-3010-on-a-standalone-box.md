---
id: STATBUS-484
title: 'The upgrade callback URL defaults to localhost:3010 on a standalone box'
status: To Do
assignee: []
created_date: '2026-10-09 07:20'
updated_date: '2026-10-09 16:28'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IMPLEMENTED (2026-10-09) at ee23bf013 on master, test-first.

The ticket's line references were slightly off; the hardcoded default was in the config generator, not installinput: cli/internal/config/config.go had StatbusURL: gen("STATBUS_URL", "http://localhost:3010"), while defaultBrowserURL three lines above was already the mode-correct external address (https://<domain> on standalone, the slot's own address otherwise).

RED, recorded before the fix, cli/internal/config/statbus_url_test.go through loadOrGenerateConfig (so the wiring is pinned, not just a helper):
  standalone:    STATBUS_URL default = "http://localhost:3010", want "https://statbus.example.no" (and != BROWSER_REST_URL "https://statbus.example.no")
  private slot:  STATBUS_URL default = "http://localhost:3010", want "http://ma.statbus.org:3020" (and != BROWSER_REST_URL "http://ma.statbus.org:3020")
  development:   STATBUS_URL default = "http://localhost:3010", want "http://local.statbus.org:3010" (and != BROWSER_REST_URL "http://local.statbus.org:3010")
  --- FAIL: TestStatbusURLDefaultsToTheExternalAddress (all three subtests)

GREEN after the fix: externalURL(mode, siteDomain, httpPort) is now the single derivation (standalone -> https://<domain>, otherwise http://<domain>:<port>) and both StatbusURL and BrowserAPIURL take their default from it, so the callback URL and the browser URL cannot drift apart again. All three subtests pass; go test ./internal/config/ ok; go build ./... clean; go test ./internal/... ./cmd/... ok.

Blast radius, as predicted: gen() only supplies a default for a missing key, so no live box changes - not our own .env.config (local.statbus.org:3000) and not any installed box. Only a fresh installation gets the corrected default, which is exactly the case the ticket was found in (474's first real install run). DoD #1: observed wrong value http://localhost:3010 on a standalone box; corrected value https://<SITE_DOMAIN>.
<!-- SECTION:NOTES:END -->
