---
id: STATBUS-089
title: >-
  maintenance-redirect-failed: site did not redirect to the maintenance page
  during the rc.04 upgrade on no.statbus.org (standalone)
status: To Do
assignee: []
created_date: '2026-06-18 12:59'
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
