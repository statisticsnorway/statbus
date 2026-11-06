---
id: STATBUS-584
title: >-
  ./sb config generate names every legacy secret in .env.config and says how to
  move each by hand
status: To Do
assignee: []
created_date: '2026-11-06T17:28:00Z'
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
- [ ] #2 The refusal says how to move them by hand (append each line to .env.credentials, then delete it from .env.config) and that ./sb install does it automatically
- [ ] #3 A Go test covers one and several secrets, red before and green after
<!-- AC:END -->
