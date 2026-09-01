---
id: STATBUS-009
title: >-
  Revisit checkMissedUpgrades semantics — boot-time claim of missed scheduled
  upgrades?
status: Done
assignee: []
created_date: '2026-06-07 20:17'
updated_date: '2026-07-06 16:14'
labels:
  - upgrade
  - investigate
dependencies: []
references:
  - cli/internal/upgrade/service.go
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a scheduled upgrade created while the service was down is picked up at boot, not silently parked for up to 6 hours.
> BENEFIT: conditional — eliminates up to 6h of unexplained upgrade delay after downtime, IF that window actually occurs in field deployments; the ticket's first job (AC#1) is to establish whether it does. If it cannot occur, the honest outcome is closure, not a fix.
> STAGE: Stage 1 (decision task).
> COMPLEXITY: architect-design (characterize + decide), then mechanic-simple if a fix is chosen.
> DEPENDS ON: nothing.
> NOTE (King, 2026-07-06): both verification prongs are IN FLIGHT — operator instance-sweep + architect code verdict; this ticket closes on their combined result (investigation-only until then).

---

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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 16:14
---
CLOSED on the two-pronged King-directed verification (2026-07-06): operator's empirical sweep (one pre-fix instance, zero since) + architect's code verdict (window provably closed by STATBUS-098's five claim paths). The King's original pushback was vindicated in both directions: the report was not a hallucination (one real instance existed), and the worry was not current (the fix had already shipped). Full verdicts in the session record; final summary carries the complete evidence chain.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: a scheduled upgrade is never silently delayed — the operator's schedule action takes effect promptly or loudly. CLOSED ON EVIDENCE (2026-07-06), the full record: REAL THEN — one genuine instance found by the operator's sweep (statbus_dev, upgrade id 7222, scheduled 2026-03-31 16:43, claimed 57m51s later; shape matches the pre-fix mechanism exactly). FIXED SINCE — the very fix this ticket proposed shipped under STATBUS-098 (commit 054c371c6, 2026-06-18): claim at boot (with the in-code comment citing this exact scenario), claim every 30s while alive, claim on NOTIFY, 6h discovery as belt-and-braces, inline via ./sb install — worst case is now 30 seconds, not 6 hours; the only deferred claims are bounded and loud (images-building grace, future schedule times). The instance predates the fix by 11 weeks (settled by commit authorship alone). VERIFIED EMPTY SINCE — operator swept dev, demo, and rune: zero instances post-fix, zero ever on demo and rune. Architect verified all five claim paths first-hand with file:line. Residual noted, deliberately not a ticket: checkMissedUpgrades' pre-fix log wording is harmless vestige, fold into the boot-claim's logging when next in the file.
<!-- SECTION:FINAL_SUMMARY:END -->
