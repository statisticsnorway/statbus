---
id: STATBUS-009
title: >-
  Revisit checkMissedUpgrades semantics — boot-time claim of missed scheduled
  upgrades?
status: To Do
assignee: []
created_date: '2026-06-07 20:17'
labels:
  - upgrade
  - investigate
dependencies: []
references:
  - cli/internal/upgrade/service.go
priority: low
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Engineer flagged this during the watchdog-reconnect diagnosis (run 27097723557): the upgrade service's checkMissedUpgrades (service.go:2694-2701) only LOGS missed scheduled rows ("Found N missed scheduled upgrade(s)") — it never CLAIMS them. A scheduled public.upgrade row created while the service was down waits up to UPGRADE_CHECK_INTERVAL (default 6h, service.go:2419-2425) for the periodic poll tick, UNLESS a NOTIFY (./sb upgrade apply) arrives or the operator runs ./sb install (inline dispatch via StateScheduledUpgrade).

QUESTION (King wants to understand the semantics + importance before deciding): is boot-time pickup of missed scheduled upgrades desired? In the real field deployments (automatic upgrades), can a scheduled row be created while the service is down and then go un-NOTIFY'd / un-installed for ~6h? If so, does that matter?

If a fix is wanted, one option the engineer noted: call d.executeScheduled(ctx) once after the initial discover() at service.go:1720 to claim missed rows at boot. This is a LATER investigation/decision task, not an immediate fix.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The real-deployment scenarios where a scheduled row is created while the service is down are characterized (can it happen in the field upgrade flows?)
- [ ] #2 A decision recorded: claim missed scheduled rows at boot (with the fix) vs leave as-is (poll-tick/NOTIFY only), with rationale
- [ ] #3 If fix chosen: it's a separate implementation task with a test
<!-- AC:END -->
