---
id: STATBUS-328
title: >-
  offer-hygiene: a row is displayed as an offer when it is not a valid upgrade
  for this box — off-channel residue in one arm, same-commit relabeling in the
  other
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-31 12:47'
updated_date: '2026-08-31 19:51'
labels:
  - upgrade
  - cli
dependencies: []
priority: medium
type: bug
ordinal: 321000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the list IS the offer (the 291 principle) — a row a box displays as "available" must be a valid upgrade for THAT box. Two verified arms where it is not, sharing one surface and one fix boundary (architect's ruling 2026-08-31, folded into one ticket at his call).

ARM 1 — STICKY OFF-CHANNEL RESIDUE. The 291 channel filter guards INTAKE only; nothing ever retires a row for being off-channel. Every retirement path keys on version ordering: supersedeBelowInstalled (service.go:4915, UPDATE at :4956-4962) and selectStaleBelowInstalled (:4819) retire rows BELOW installed; the dismissal sweeps (:1610, :5403) are not channel-based. d.channel appears ONLY at intake and announce: FilterTagsByChannel in discover() (:4458), TagMatchesChannel in scheduleStep (:5570) — never in a retirement predicate. So on a stable box, an RC row registered before the filter arrived sits ABOVE the installed version, is never superseded, and stays available indefinitely. CONFIRMED LIVE (operator read, 2026-08-31): et/jo/ug display v2026.08.1-rc.01 residue rows while their filter provably works (zero RC discoveries post-v2026.08.0, discovered_at). Mitigation on record so this is not over-rated: the 291 announce at :5570 fires if an operator schedules one — the harm is a misleading offer, not a silent wrong install.

ARM 2 — SAME-COMMIT RELABELING OFFERED AS AN UPGRADE. An "upgrade" that changes no code is not an upgrade: rc.01 and v2026.08.1 are two names for commit 0da0f202dcf3, and selectNewestDownloadCandidate (service.go:4777) orders LABELS, not code — the 293 ruling (the COMMIT is authoritative, not the tag) applied to the offer surface. Not merely transient: the box's self-view (git-describe CommitVersion, commit.go:37) re-derives only on service restart, days away on a production box; throughout, the offer is visible and actionable, costing a real maintenance window (backup/checkout/restart) to change a string. Fix shape: short-circuit on commit identity — candidate commit_sha == the box's installed commit → never an offer. Builder must confirm whether the service already holds its own HEAD SHA (install.go:2302 already does git rev-parse HEAD, so it is cheaply available).

WHAT IS ACHIEVED: no box displays an offer it should not act on — the shelf matches the intake policy, and no one is invited to spend a maintenance window installing a name.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Arm 1: an off-channel available/scheduled row is retired (or hidden from the offer surface) on a box whose channel excludes it, with a test proving pre-filter residue disappears and on-channel rows survive
- [x] #2 Arm 2: a candidate whose commit_sha equals the box's installed commit is never displayed or offered, with a test on the dual-tag (rc + release same commit) case
- [x] #3 The 291 announce at scheduleStep remains intact — retirement/hiding must not remove the announce for anything still schedulable
- [x] #4 No retirement decision compares by version-string channel guessing — channel membership and commit identity are the only new predicates
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-31 12:49
---
Architect's fix-shape narrowing for Arm 1 (2026-08-31, after live evidence): intake needs nothing more (filter proven working). What is missing is RETRACTION of pre-filter rows. A migration CANNOT do this — the box's channel lives in .env, not the database, so a repair migration has nothing to filter on. The retraction must live where the channel is known: the service. Right shape: a startup sweep retiring off-channel 'available' rows — NOT a standing self-heal, because it applies the same declared channel policy discover() applies at intake (consistent application of declared policy is not repair; same reasoning that settled 325's derivation question).
---

created: 2026-08-31 19:42
---
Foreman (2026-08-31 evening): King dispatched the remaining arm for the coming candidate. SCOPE NOW: Arm 1 only, narrowed — rc-shaped rows on a STABLE-channel box are the sole off-channel case (nested semantics landed in 307 at 7816a7654 made stable-on-prerelease legitimate; Arm 2's same-commit short-circuit ALSO landed in 307 — AC#2 is satisfied there). Fix shape per the architect's narrowing (comment #1): retraction lives in the service where the channel is known (a migration cannot see .env); a startup sweep applying the same declared channel policy discover() applies at intake — consistent policy application, not a standing self-heal. Assigned: engineer.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
COMPLETE across two landings. Arm 2 (same-commit short-circuit) landed inside STATBUS-307 at 7816a7654: candidate commit == the running binary's ldflags commit → never an offer. Arm 1 landed at 572b11467: retireOffChannelOffers runs at service startup BEFORE the first discovery, retiring 'available' rows whose tags all fail TagMatchesChannel — the ONE membership definition, shared with intake and the announce. State is 'skipped' (schema-ruled: dismissed structurally requires a failure; superseded would record a replacement that never happened; skipped is a decision-state and this is a policy decision). Never touched: scheduled rows (human decisions taken with the 291 announce in view — a test pins it) and untagged rows (operator SHA-registrations with no membership to test). THE SELF-CAUGHT CATASTROPHE, on record: a channel admitting nothing (unknown value, or a developer's 'local') inverts intake's safe direction into sweep-everything at retirement — the channelAdmitsAnything guard derives sweepability from TagMatchesChannel itself, preserving the single definition. The 242 rewind audit carries the honest bound: re-derived per START not per tick; a restore without a restart leaves stale offers until the next start (exactly the pre-fix condition, still announce-guarded), never a wrong install. Under the new nested channels the sweep also makes future prerelease→stable narrowing transitions clean — the direction-asymmetry case the architect recorded. Foreman-reviewed line by line; seven tests re-run independently by name; vet/gofmt clean.
<!-- SECTION:FINAL_SUMMARY:END -->
