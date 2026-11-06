---
id: STATBUS-584
title: >-
  ./sb config migrate moves legacy secrets, shared by install and upgrade;
  config generate names every secret and points to it
status: Done
assignee: []
created_date: '2026-11-06T17:28:00Z'
updated_date: '2026-11-06T21:44:00Z'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 496204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by hibiscus 2026-11-06 (owner request 17:22; evidence /Users/jhf/ssb/statbus/tmp/566-4g/install-log.md). cli/internal/config/config.go:388-397 refuses when .env.config holds GITHUB_TOKEN, SLACK_TOKEN or SEQ_API_KEY, but names only the FIRST it finds and says only 'run ./sb install to migrate it'. On a dev box where install cannot finish (STATBUS-585) the operator is stuck, and after moving SLACK_TOKEN a second run refused on SEQ_API_KEY. Owner decision: the migration stays in install (generate does not rewrite operator files); the refusal names every secret found and says how to move it by hand.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With two or three legacy secrets in .env.config, ./sb config generate refuses once and names every one of them
- [x] #2 A Go test covers one and several secrets, red before and green after
- [x] #3 ./sb config migrate moves every legacy secret from .env.config to .env.credentials (mode 0600), says what it moved, and a second run moves nothing
- [x] #4 One function (config.MigrateSecrets) is used by ./sb config migrate, the installer and the upgrader; the hidden config generate --migrate-legacy-secrets flag is gone
- [x] #5 It works the same on a development Mac: ./sb config migrate then ./sb config generate succeed without ./sb install
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-06 17:51: moving secrets is config maintenance, so it gets its own command, ./sb config migrate, with one shared implementation used by the installer and upgrader (single source of truth). config generate never edits operator files; its refusal names every secret and the migrate command. Hibiscus told.

2352e682d. config.MigrateSecrets is the one migration: ./sb config migrate, the installer (generateInstallerConfig), install crash recovery (regenerateCrashRecoveryConfig) and the upgrader (recovery boot and post-swap target regeneration) call it; the --migrate-legacy-secrets flag is hidden and kept only for upgraders from earlier releases (runs the same function). Refusal names every secret: 'SLACK_TOKEN and SEQ_API_KEY in .env.config are secrets and belong in .env.credentials. Run cd <dir> && ./sb config migrate to move them.' Tests red (tmp/584-red.log) then green (tmp/584-green.log, tmp/584-green-cmd.log: config, cmd, upgrade ok). Mac end-to-end with the built ./sb: tmp/584-mac-e2e.log.

rc.18 gate GREEN: Release Fleet Orchestrator 42290374739 for v2026.11.1-rc.18 (360b1a253); Upgrade Arc Harness 42292586368 incl. postswap-migration-ceiling success; LXD Fork Fleet 42292492037. (first gate containing it; rc.17 gate failed on the unrelated STATBUS-586).
<!-- SECTION:NOTES:END -->
