---
id: STATBUS-333
title: >-
  schedule-function-one-door: one database-side schedule function both UI and
  CLI call
status: To Do
assignee: []
created_date: '2026-09-01 09:46'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 326000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: scheduling a candidate is written differently per door. The CLI's promoteExistingCandidate (cli/internal/upgrade/service.go:5180) clears the full lifecycle (started_at, completed_at, error, rolled_back_at, skipped_at, dismissed_at, superseded_at, recovery budget) and then supersedes older candidates (service.go:5168). The UI writes only {state:'scheduled', scheduled_at} (app/src/app/admin/upgrades/page.tsx:746-750), so a UI schedule cannot retry a ran/failed row (started_at/error survive), cannot un-park, and never supersedes older candidates.

Fix: move the schedule-write semantics into one database-side function (e.g. public.upgrade_schedule(id)) carrying lifecycle reset, un-park, and supersede-older. UI calls it via PostgREST RPC; the CLI/service calls the same function. Delete the per-door UPDATEs so the doors cannot differ.

Acceptance: scheduling a previously-failed or parked row from the UI button retries it cleanly (started_at/error/park cleared), older available candidates go superseded on both doors, and the state CASE in cli/cmd/upgrade.go renders the re-scheduled row as scheduled, not its stale decision.
<!-- SECTION:DESCRIPTION:END -->
