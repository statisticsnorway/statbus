---
id: STATBUS-106
title: >-
  channel-only-bless: migration-fix decision reads UPGRADE_CHANNEL only; safe
  default local (dev), stable (production)
status: To Do
assignee: []
created_date: '2026-06-21 18:59'
labels:
  - upgrade
  - migration
  - config
dependencies: []
references:
  - cli/internal/migrate/migrate.go
  - cli/internal/config/config.go
  - cli/cmd/install.go
priority: high
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GOAL (King's principle): the box's decision on an immutable migration whose content changed (a sanctioned fix) — bless / re-run / stop-and-ask-the-human — depends ONLY on UPGRADE_CHANNEL (the upgrade axis), never on CADDY_DEPLOYMENT_MODE (the front-door / web-serving axis). The deployment mode touches only the front door, never the upgrade logic.

THE BUG TODAY (verified):
1. migrationChannelClass (cli/internal/migrate/migrate.go) reads CADDY_DEPLOYMENT_MODE (development -> localDev) — a front-door setting leaking into the upgrade logic.
2. config.go writes UPGRADE_CHANNEL to .env at :708 with the comment "always written to .env so the service never silently defaults" — it writes UPGRADE_CHANNEL=stable for EVERY mode. So a DEVELOPMENT box gets UPGRADE_CHANNEL=stable. The deployment-mode check in (1) is the patch hiding this — it forces localDev despite the stable channel.
3. Inconsistency: config.go:374 wraps the upgrade settings in `if mode != "development"` (intending dev-excluded), but the actual .env write at :708 ignores that and writes stable for all modes.
4. The installer does NOT set UPGRADE_CHANNEL (no write in install.go) — every box relies on the :708 stable default.

THE FIX (precise, two edits):
A. cli/internal/migrate/migrate.go — migrationChannelClass: DELETE the CADDY_DEPLOYMENT_MODE read. Classify purely on UPGRADE_CHANNEL:
   - edge -> channelEdge
   - stable | prerelease -> channelRelease
   - default (local / unset / unknown) -> channelLocalDev
   Update the doc-comment (drop the dev-mode-first precedence story) + migration_channel_test.go.
B. cli/internal/config/config.go — make the UPGRADE_CHANNEL default MODE-AWARE, reconciling :374 (already non-dev-only intent) with :708 (currently always-stable): development -> "local"; non-development (standalone / private) -> "stable". One consistent rule across :374 and :708.

RESULT (precise per path):
- Internet / standalone (or cloud/private) install -> UPGRADE_CHANNEL=stable -> channelRelease -> blesses sanctioned migration-fixes.
- Local dev checkout (development mode) -> UPGRADE_CHANNEL=local -> channelLocalDev -> stops and asks the human; never auto-mutates.
- The deployment mode is never read in the bless logic. Test == production for the upgrade logic: the upgrade arc can exercise the release-bless by setting UPGRADE_CHANNEL=stable on a development-mode box, with no harness mode change.

SAFETY (no transition / no breakage):
- Existing production boxes (non-development) keep UPGRADE_CHANNEL=stable -> still bless. No flip.
- Existing dev boxes were localDev via the deleted mode-check; now localDev via UPGRADE_CHANNEL=local -> same behavior.

CONTEXT: this is "Thing 1" (the bless-decouple), King-approved 2026-06-21, completed with the precise channel-default enforcement the King interrogated (config.go:708 wrote stable for every mode — the shortcut the architect had missed). Optional hardening (not required): the standalone/cloud installer could ALSO write UPGRADE_CHANNEL=stable explicitly into .env.config so production declares its channel rather than relying on a default.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 migrationChannelClass reads UPGRADE_CHANNEL only (CADDY_DEPLOYMENT_MODE deleted); classifies edge->edge, stable|prerelease->release, default->localDev; doc-comment + migration_channel_test.go updated
- [ ] #2 config.go UPGRADE_CHANNEL default is mode-aware (development->local, non-development->stable); :374 and :708 reconciled to one consistent rule
- [ ] #3 Verified: a development box generates UPGRADE_CHANNEL=local and classifies localDev (never blesses); a standalone/private box generates stable and blesses
- [ ] #4 Existing behavior preserved: non-development still stable->blesses; development still localDev (no flip, no breakage)
- [ ] #5 gofmt + go vet + go test (migrate + config) green
<!-- AC:END -->
