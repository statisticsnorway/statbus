---
id: STATBUS-106
title: >-
  channel-only-bless: migration-fix decision reads UPGRADE_CHANNEL only; safe
  default local (dev), stable (production)
status: Done
assignee:
  - engineer
created_date: '2026-06-21 18:59'
updated_date: '2026-06-21 19:10'
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
- [x] #1 migrationChannelClass reads UPGRADE_CHANNEL only (CADDY_DEPLOYMENT_MODE deleted); classifies edge->edge, stable|prerelease->release, default->localDev; doc-comment + migration_channel_test.go updated
- [x] #2 config.go UPGRADE_CHANNEL default is mode-aware (development->local, non-development->stable); :374 and :708 reconciled to one consistent rule
- [x] #3 Verified: a development box generates UPGRADE_CHANNEL=local and classifies localDev (never blesses); a standalone/private box generates stable and blesses
- [x] #4 Existing behavior preserved: non-development still stable->blesses; development still localDev (no flip, no breakage)
- [x] #5 gofmt + go vet + go test (migrate + config) green
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-06-21 19:01
---
▶ DISPATCHED 2026-06-21 — King-approved via architect relay (supersedes the earlier bless-decouple readiness note; 106 is the complete version: decouple + channel-default reconciliation). Engineer building Edit A (migrate.go migrationChannelClass: delete the CADDY_DEPLOYMENT_MODE read at :1516, classify on UPGRADE_CHANNEL only, update doc-comment :1497-1510 + stale comment :1421 + migration_channel_test.go) and Edit B (config.go: reconcile :374/:376 vs :708 into one mode-aware rule — development→local, non-development→stable). Installer hardening explicitly OUT OF SCOPE. Foreman gates (gofmt/vet/go test migrate+config) + commits; engineer does not commit. Logical change only, gofmt churn excluded.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE — committed 81a9082b3, foreman-gated green. Migration-fix bless decision now reads UPGRADE_CHANNEL only; deployment mode is fully decoupled from the upgrade logic.

EDIT A (cli/internal/migrate/migrate.go): deleted the CADDY_DEPLOYMENT_MODE read in migrationChannelClass; classifies on UPGRADE_CHANNEL alone (edge→edge, stable|prerelease→release, local/unset/unknown→localDev). Doc-comment rewritten to the channel-only story; stale :1421 inline comment fixed. The out-of-scope :967 mode read was left untouched. migration_channel_test.go rewritten — dev-mode-wins cases removed; new cases positively prove mode is IGNORED (development+edge→edge, development+stable→release).

EDIT B (cli/internal/config/config.go): UPGRADE_CHANNEL default is now mode-aware and ALWAYS written — development→local, non-development→stable — reconciled across both write paths (loadOrGenerateConfig .env.config gen ~:374 and the .env buffer fallback ~:716 via cfg.CaddyDeploymentMode). Fixes the latent bug where :708 wrote stable for every mode.

GATE (foreman, GOTOOLCHAIN=go1.25.5): gofmt clean on migrate files; config.go gofmt drift confirmed PRE-EXISTING (regions 53/76-136/141-157/360-367/465-475/621-650/807-818, none overlap the logical hunks 371-390/716-727) and excluded from the commit. go vet OK; go test ./internal/migrate/... ./internal/config/... OK (TestMigrationChannelClass re-run fresh -count=1, all 11 cases + NoEnvFile PASS); go build ./... OK.

NO FLIP: existing non-dev boxes stay stable→release (bless); existing dev boxes stay localDev (now via channel=local). Unblocks the held STATBUS-102 end-to-end bless proof: the arc can exercise release-bless on a development-mode box by setting UPGRADE_CHANNEL=stable. Installer hardening (install.go writing UPGRADE_CHANNEL into .env.config) deliberately left out of scope.

NOT YET PUSHED — awaiting King's word on push timing (origin/master).
<!-- SECTION:FINAL_SUMMARY:END -->
