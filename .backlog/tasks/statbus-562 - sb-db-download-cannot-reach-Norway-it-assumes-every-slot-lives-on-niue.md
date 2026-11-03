---
id: STATBUS-562
title: 'sb db download cannot reach Norway: it assumes every slot lives on niue'
status: To Do
assignee: []
created_date: '2026-11-03T22:01:00Z'
updated_date: '2026-11-03T22:01:00Z'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 485204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
./sb db download <code> connects to statbus_<code>@niue.statbus.org (cli/cmd/db.go:313-315). Norway moved to the standalone box rune.statbus.org (statbus@rune, db statbus_no, doc/CLOUD.md), so ./sb db download no fails with 'Permission denied (publickey)'. Found 2026-11-03 while fetching Norway for STATBUS-558; worked around by copying rune's scheduled backup dbdumps/no_<ts>.pg_dump with scp.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ./sb db download no fetches a fresh dump from rune.statbus.org
- [ ] #2 The host and user for each slot come from one place that knows about standalone boxes, not a hardcoded niue
- [ ] #3 Downloading a niue slot (e.g. dev) still works
<!-- AC:END -->
