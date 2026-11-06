---
id: STATBUS-584
title: >-
  ./sb config migrate moves legacy secrets, shared by install and upgrade;
  config generate names every secret and points to it
status: In Progress
assignee: []
created_date: '2026-11-06T17:28:00Z'
updated_date: '2026-11-06T17:55:00Z'
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
- [ ] #1 With two or three legacy secrets in .env.config, ./sb config generate refuses once and names every one of them
- [ ] #2 A Go test covers one and several secrets, red before and green after
- [ ] #3 ./sb config migrate moves every legacy secret from .env.config to .env.credentials (mode 0600), says what it moved, and a second run moves nothing
- [ ] #4 One function (config.MigrateSecrets) is used by ./sb config migrate, the installer and the upgrader; the hidden config generate --migrate-legacy-secrets flag is gone
- [ ] #5 It works the same on a development Mac: ./sb config migrate then ./sb config generate succeed without ./sb install
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-06 17:51: moving secrets is config maintenance, so it gets its own command, ./sb config migrate, with one shared implementation used by the installer and upgrader (single source of truth). config generate never edits operator files; its refusal names every secret and the migrate command. Hibiscus told.
<!-- SECTION:NOTES:END -->
