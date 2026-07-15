---
id: STATBUS-184
title: >-
  harness-tip-race: scenario runs build sb from the local tip while the VM
  checks out origin — backlog auto-commits make runs fail on freshness
status: To Do
assignee: []
created_date: '2026-07-14 16:47'
updated_date: '2026-07-15 08:32'
labels:
  - install-recovery
  - harness
  - tooling
dependencies: []
priority: low
ordinal: 185000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a scenario/arc dispatch is self-consistent by construction — the binary the harness uploads always resolves in the checkout the VM gets, regardless of what the team's backlog auto-commits are doing to the local tip.
> WHERE THIS STANDS (2026-07-15): FIX SHIPPED at 347cc7e85 — the root cause was a TOCTOU race against STATBUS-132's existing freshness guard (the guard checked, the tip moved, the build used the moved tip); the fix re-checks at the commit-pin point, so the SHA the harness builds is the SHA the run uses. Every subsequent arc/scenario dispatch has run through the fixed path. AC#2's explicit oracle (a deliberately unpushed local commit → loud refusal naming `git push`, or a self-consistent run) remains to be observed on one deliberate run.
> FOUND: 2026-07-14, two burned VM runs back-to-back on 4-flagless-selfheal-at-target — both uploaded an sb built at a local-only backlog auto-commit against a VM at a different origin tip; both died on the staleness guard's `git diff` exit 128 ("bad object <build commit>"). In a busy team session the local tip moves every few minutes; the dispatch-window race was structural, not operator sloppiness.
> COMPLEXITY: mechanic-small (shipped).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fix shape picked (refuse-on-unpushed vs build-from-origin) and implemented in the scenario/arc dispatch path
- [ ] #2 A dispatch with a deliberately unpushed local commit either refuses loudly naming the remedy, or succeeds self-consistently — proven by a run
<!-- AC:END -->
