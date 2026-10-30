---
id: STATBUS-544
title: Remove the hidden sb upgrade service alias one release after the next
status: To Do
assignee: []
created_date: '2026-10-30T12:33:00Z'
updated_date: '2026-10-30T12:33:00Z'
labels:
  - enhancement
dependencies: []
priority: medium
type: chore
ordinal: 470204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Why: STATBUS-527 renamed the upgrader to noun commands (sb upgrader install|start|stop|status|run). Units installed before 527 (statbus-upgrade@.service) run ExecStart='sb upgrade service', so cli/cmd/upgrade.go keeps that as a hidden alias of 'sb upgrader run'. Owner decision 2026-10-30: remove the alias in the release after the next one, so every box that upgrades through the next release already runs statbus-upgrader@.service.

Risk to prove away: a box still on a pre-527 release that upgrades straight to the release without the alias. During that upgrade the old unit restarts the new ./sb with 'upgrade service'; if the alias is gone before the unit is migrated, the upgrader crash-loops.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cli/cmd/upgrade.go no longer registers the 'service' subcommand, and the comments in upgrade.go and upgrader.go that point at this follow-up are removed
- [ ] #2 A real upgrade arc from the newest release that still installs statbus-upgrade@.service to a candidate without the alias ends with only statbus-upgrader@ active and the upgrade completed (run ID recorded)
- [ ] #3 Shipped in a stable release later than the next one after 2026-10-30, with that release tag recorded in the notes
<!-- AC:END -->
