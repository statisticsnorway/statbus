---
id: STATBUS-579
title: Upgrade completion finishes ledger cleanup on a live database connection
status: In Progress
assignee: []
created_date: '2026-11-07T21:52:00Z'
labels:
  - upgrade
  - recovery
  - release
dependencies: []
priority: high
type: bug
ordinal: 506204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed on real Norway rc02-to-rc03 upgrade at 2026-11-07 21:47:36 UTC. Upgrade completed and serves correctly, but clear-install-failure banner, explicit frontend notification, supersede-older/completed-prerelease and retention queries all use a cached closed queryConn after the database restart. Both rc02 and rc03 remain completed. Terminal row and read-only OFF use fresh connections and succeeded. Evidence tmp/rune-measure/final-rc03/dispatch-complete.log:510-519 and subsequent read-only ledger query. Fix now before stable promotion, without changing domain data or interrupting acceptance recalculation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A behavioral regression fails before the fix when completion succeeds through a fresh terminal session while the cached pass connection is closed.
- [ ] #2 Successful completion clears any stale failure banner, publishes the completion notification and retires obsolete release rows through a live bounded connection, with recovery/completion paths covered.
- [ ] #3 Relevant Go/live-database tests and exact-SHA CI pass, and a candidate-built real upgrade demonstrates the completed ledger and cleanup outcomes.
<!-- AC:END -->
