---
id: STATBUS-089
title: >-
  maintenance-redirect-failed: site did not redirect to the maintenance page
  during the rc.04 upgrade on no.statbus.org (standalone)
status: To Do
assignee: []
created_date: '2026-06-18 12:59'
updated_date: '2026-06-18 13:07'
labels:
  - upgrade-ui
  - maintenance
  - standalone
  - post-rc.04
dependencies: []
priority: high
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OBSERVED (King, no.statbus.org = standalone/rune box, rc.04 upgrade, 2026-06-18): during the upgrade, https://no.statbus.org/ did NOT redirect to the maintenance page. Users hitting the site mid-upgrade would see errors / a broken site instead of a maintenance notice.

NOTE: not flagged on dev.statbus.org (multi-tenant/private mode) — so this may be STANDALONE-mode-specific. dev (private, behind host proxy) vs no (standalone, public HTTPS via Caddy + Let's Encrypt) have different Caddy configs.

INSPECTION (delegated):
- How is the maintenance page served during an upgrade? (Caddy/proxy-level intercept vs app-level redirect vs a maintenance flag/file the proxy checks.)
- What sets/clears maintenance mode around an upgrade (the upgrade service? a flag file? a Caddy reload?).
- Why did it fail in STANDALONE mode? Compare the standalone Caddy template/maintenance path vs the cloud/private one (cli/src/templates/*.caddyfile.ecr; doc on deployment modes).

Real during-upgrade UX failure (users see errors, not maintenance). Post-rc.04; not a data-loss issue but operator/user-facing during every upgrade.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE (mechanic, 2026-06-18) — CONFIG DRIFT on rune, not an rc.04 code bug.
Mechanism: setMaintenance() (cli/.../exec.go:212-236) writes/removes ~/maintenance (=/home/statbus/maintenance). Caddy serves maintenance.html (503) via `try_files /home/statbus/maintenance` (standalone.caddyfile.ecr:75-87, the CURRENT repo template).
Drift: rune's DEPLOYED caddy/config/standalone.caddyfile uses an OLD path — `@maintenance { file /statbus-maintenance/active }` (an older Docker bind-mount convention). The service writes ~/maintenance; Caddy watches /statbus-maintenance/active → mismatch → maintenance never activates. Repo template is correct; the deployed config predates the convention change.

IMMEDIATE FIX (rune): regenerate the Caddyfile from the current template — `./sb config generate` (or re-run the idempotent install) on rune. This is a PRODUCTION change (foreman won't SSH-write; King to run or approve).

DEEPER PRODUCT GAP (Albania-relevant, route to architect): the rc.04 UPGRADE did NOT regenerate the Caddy config from the new version's template, so a template/convention change (here: the maintenance path) does NOT propagate to existing boxes on upgrade. Question: should the upgrade flow regenerate config (Caddyfiles/.env) from the new version's templates so drift self-heals everywhere? If not, every template change is a latent footgun on already-deployed boxes (incl. Albania). Confirm whether the upgrade's install-fixup runs config generate + why it didn't heal this.
<!-- SECTION:NOTES:END -->
