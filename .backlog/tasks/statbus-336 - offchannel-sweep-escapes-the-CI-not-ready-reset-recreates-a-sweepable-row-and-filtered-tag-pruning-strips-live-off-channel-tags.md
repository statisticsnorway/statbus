---
id: STATBUS-336
title: >-
  offchannel-sweep-escapes: the CI-not-ready reset recreates a sweepable row,
  and filtered-tag pruning strips live off-channel tags
status: To Do
assignee: []
created_date: '2026-09-02 08:17'
updated_date: '2026-09-02 08:28'
labels:
  - upgrade
  - defect
dependencies: []
priority: high
type: bug
ordinal: 329000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two escapes found by adversarial review of the READY-cutoff fix (Sol xhigh, 2026-09-02), both mishandling a deliberately scheduled row whose tag the box's channel filter excludes:
1. TAG PRUNING (not narrow — silent identity corruption): discovery hands the CHANNEL-FILTERED tag list to pruneDeletedTags (cli/internal/upgrade/service.go:4687), whose only question is "was this tag deleted IN GIT?". A channel-excluded tag exists in git but is absent from the filtered list, so an ordinary discovery tick strips it from the row and demotes release_status to commit. KING'S RULING 2026-09-02: always keep all git tags; delete only tags actually missing from git. The channel says what to DISPLAY/offer, never what exists. Fix: pass the unfiltered git tag list to pruneDeletedTags.
2. CI-NOT-READY STEP-BACK (narrow): when a scheduled row's images are not ready, executeUpgrade resets it to state='available' with old discovered_at (service.go:6295) — recreating the sweepable shape, so the next boot's off-channel sweep retires the operator's manual schedule to skipped. KING'S DIRECTION: prefer KEEP IT SCHEDULED — the operator's intent has not changed because a download is not done; the claim loop retries when artifacts turn ready. Open design point for the architect: bounded patience without a retry counter — time-based (e.g. scheduled_at age or a waiting_since timestamp surfaced in UI/CLI rather than auto-give-up), and whether a standing scheduled row wrongly blocks the upgrade_single_scheduled slot or graceful supersede; rule the honest shape, no counters.

Acceptance: a manually scheduled channel-excluded row survives (tags intact, never skipped, still visibly scheduled or explicitly waiting) across images-not-ready → daemon restart → discovery ticks, and proceeds when images turn ready; pruneDeletedTags proven to never strip a tag that exists in git (channel irrelevant); a genuinely git-deleted tag is still pruned; existing off-channel sweep tests stay green.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
King's design confirmation (2026-09-02): visibility over automation. Keep the row scheduled; surface its age from scheduled_at in UI + CLI list (e.g. 'scheduled 3 days ago, images still building') so a long wait is DETERMINABLE — at that point no automation or counting gives a reasonable answer, a human decides. Expected common resolution: the fix ships as a newer candidate and graceful supersede resolves the stuck row naturally. Architect verifies the single-scheduled slot + supersede interaction; no counters, no auto-give-up.
<!-- SECTION:NOTES:END -->
