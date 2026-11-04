---
id: STATBUS-562
title: 'sb db download cannot reach Norway: it assumes every slot lives on niue'
status: Done
assignee: []
created_date: '2026-11-03T22:01:00Z'
updated_date: '2026-11-04T00:10:00Z'
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
- [x] #1 ./sb db download no fetches a fresh dump from rune.statbus.org
- [x] #2 The host and user for each slot come from one place that knows about standalone boxes, not a hardcoded niue
- [x] #3 Downloading a niue slot (e.g. dev) still works
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fix fc957cb0d (pushed to master). Added cli/internal/fleet, which parses cloud.sh FLEET_REGISTRY (the fleet operator tool's one slot table) and resolves code -> ssh target/domain/auth; database name stays statbus_<code> and the checkout dir fleet.RemoteWorkdir. `sb db download` and its log companion now use the resolved target (downloadLogsCompanion takes fleet.Slot); remote restore (`sb db restore --to`) uses the same resolver. Unknown or malformed slots fail loudly instead of synthesizing a niue address.

RED: tmp/test-fleet-red.log (undefined LoadFile) before implementation. GREEN: go test ./internal/fleet/ ./cmd/ -> ok both (tmp/test-cli-fleet-cmd-final.log). ./dev.sh build-sb ok (v2026.11.1-rc.04-20-g652ec4ca0).

Acceptance 2026-11-03 23:14-23:18 UTC on the real box: `./sb db download no` -> dbdumps/no_20261103_231451.pg_dump 1.4 GB (pg_restore -l: dbname statbus_no) + no_20261103_231451.logs.tar.gz 152 KB; `./sb db dumps list` showed it. Both files deleted after verification. SSH prechecks: statbus@rune.statbus.org -> ok, statbus_dev@niue.statbus.org -> ok (no dev download). Artifact log: tmp/statbus-562-download-no.log.

2026-11-04 verified by hibiscus: go test ./internal/fleet/ ./cmd/ -run 'Fleet|Download' ok; fc957cb0d is in v2026.11.1-rc.05 (tag 95bbd09cb, Fast Tests green on that SHA). ox's acceptance on rune recorded above.
<!-- SECTION:NOTES:END -->
