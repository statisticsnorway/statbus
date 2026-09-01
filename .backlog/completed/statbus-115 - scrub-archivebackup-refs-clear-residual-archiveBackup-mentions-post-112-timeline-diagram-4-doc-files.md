---
id: STATBUS-115
title: >-
  scrub-archivebackup-refs: clear residual archiveBackup mentions post-112
  (timeline diagram + 4 doc/ files)
status: Done
assignee: []
created_date: '2026-06-29 16:22'
updated_date: '2026-07-06 15:59'
labels:
  - docs
  - backup
  - cleanup
dependencies: []
references:
  - doc/upgrade-timeline.md
  - doc/recovery/
  - doc/diagrams/upgrade-timeline.plantuml
  - STATBUS-112
priority: low
ordinal: 115000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why
STATBUS-112 removes `archiveBackup` (the forensics tar) + retires its arc scenario. The engineer's pass correctly stayed hands-off the architect's docs + the just-committed diagrams, leaving residual archiveBackup refs that would STRAND (describe a now-removed function/scenario):

- **Timeline diagram** (committed 415535693) still draws the `3-postswap-archivebackup-watchdog` stall-step / test note — the scenario is RETIRED in 112. → DROP. (Handled promptly via the mechanic + architect gate, not this ticket — listed for completeness.)
- **doc/upgrade-timeline.md** + **doc/recovery/{upgrade-resume-structural-whole, recovery-injection-scope-a-comprehensive, recovery-arc-flaw-timeoutstartsec}.md** — residual archiveBackup refs; SOME are legitimate historical FIX-A / n-watchdog plan record.

## Principle (per-ref judgment)
- CURRENT-behavior refs (archiveBackup as a live step; the archivebackup-watchdog scenario as live coverage) → REMOVE / update (it's gone).
- HISTORICAL record (the FIX-A / n-watchdog bug story) → KEEP as history, marked superseded: "archiveBackup — removed in STATBUS-112".

## Verify
`grep -rE 'archiveBackup|archive-backup-stall' doc/ doc/diagrams/` returns only intentional, marked-historical mentions; the timeline diagram no longer draws the stall-step. Architect spot-checks.

Low priority (some are historical; no functional impact) — fits the King's deferred doc/backlog-language cleanup pass.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Current-behavior archiveBackup refs in doc/upgrade-timeline.md + the 3 doc/recovery/ files are removed/updated (the function + its scenario are gone)
- [ ] #2 Historical FIX-A / n-watchdog references are KEPT but marked superseded ('removed in STATBUS-112'), not deleted (preserve the bug-history record)
- [ ] #3 grep over doc/ + doc/diagrams/ shows only intentional marked-historical mentions; architect spot-checks the result
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PARTIAL (architect, 2026-06-30, pre-context-clear): doc/upgrade-timeline.md — the retired `archive-backup-stall-active-phase-watchdog` scenario-class table row DROPPED (committed with the architect's final docs). The 3 doc/recovery/* (upgrade-resume-structural-whole / recovery-injection-scope-a-comprehensive / recovery-arc-flaw-timeoutstartsec) are committed historical investigation records (FIX-A / injection-scope / arc-flaw) — their archiveBackup refs are KEEP-as-history; the 'removed in STATBUS-112' superseded-marking + any per-ref current-vs-historical judgment on those 3 REMAINS for the cleanup pass (note recovery-injection-scope's scenario inventory: scenario 26 / the archive-backup-stall class count may want a current-status update).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MERGED into STATBUS-043: same aim (docs describe only the shipped system), same owner, partially done — a named archive/backup-refs residual for the 043 sweep.
<!-- SECTION:FINAL_SUMMARY:END -->
