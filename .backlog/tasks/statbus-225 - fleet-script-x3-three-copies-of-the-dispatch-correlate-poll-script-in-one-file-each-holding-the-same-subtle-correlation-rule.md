---
id: STATBUS-225
title: >-
  fleet-script-x3: three copies of the dispatch-correlate-poll script in one
  file, each holding the same subtle correlation rule
status: To Do
assignee: []
created_date: '2026-08-18 09:54'
labels:
  - ci
  - release
dependencies: []
references:
  - .github/workflows/release-fleet-orchestrator.yaml
priority: low
type: chore
ordinal: 225000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: the release fleet orchestrator dispatches three fleets one at a time. Each of its three jobs runs the same inline script: dispatch with retry, correlate the run GitHub refuses to hand back an id for, then poll that run to its conclusion and branch on it explicitly.

WHAT GOES WRONG: the script exists three times in the same file, differing only in a workflow filename and a poll budget. The correlation step in particular encodes a subtle rule about which run is ours, and three copies of a subtle rule drift — a fix applied to one dispatch step and not the others is invisible in review and silently changes only one third of the chain's behaviour.

THE DETAIL: the inline form was a deliberate choice, matching deploy-to-*.yaml's convention that these dispatch/poll loops live at their call site, and the jobs genuinely need no checkout so an external script would cost one for nothing. That reasoning holds across separate files, where each copy has an independent reason to exist. Inside one file, three near-identical ~70-line blocks are one script with three call sites. The pressure is already visible: the STATBUS-214 review's correlation amendment has to be written three times, correctly, or the chain behaves differently depending on which fleet is running.

THE FIX: extract to a local composite action (for example .github/actions/dispatch-fleet-and-wait) taking the workflow file, ref, commit and poll budget, and call it from all three jobs. The cost is one checkout per job — seconds — against removing about 140 duplicated lines and giving the correlation rule a single home.

WHY THAT HELPS: the next change to how a fleet is dispatched, correlated or polled is made once and applies to all three, and a reviewer reads one implementation instead of diffing three blocks against each other to confirm they still agree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The dispatch/correlate/poll logic exists once, called by all three orchestrator jobs with per-fleet parameters
- [ ] #2 Behaviour is unchanged: same retry counts, same correlation rule, same explicit conclusion branching, same per-fleet poll budgets
- [ ] #3 A failed or cancelled fleet run still stops the chain loudly, and the run URL is still surfaced per fleet
<!-- AC:END -->
