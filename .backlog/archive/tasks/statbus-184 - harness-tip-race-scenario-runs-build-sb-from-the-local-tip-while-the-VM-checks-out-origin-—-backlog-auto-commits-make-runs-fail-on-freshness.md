---
id: STATBUS-184
title: >-
  harness-tip-race: scenario runs build sb from the local tip while the VM
  checks out origin — backlog auto-commits make runs fail on freshness
status: Done
assignee: []
created_date: '2026-07-14 16:47'
updated_date: '2026-07-20 15:31'
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
- [x] #2 A dispatch with a deliberately unpushed local commit either refuses loudly naming the remedy, or succeeds self-consistently — proven by a run
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-20 15:31
---
AC#2 PROVEN BY A RUN (2026-07-20, foreman). Method: pushed all pending local commits first (origin tip 3747eb117), created a deliberate EMPTY unpushed commit 7795036c9, then dispatched a real run (bash run.sh 0-happy-install). The preflight REFUSED in seconds, before any VM: banner names the exact unpushed HEAD (7795036c9...), the consequence it prevents ('the VM's clone has only origin, so an unpushed HEAD dies VM-side with fatal: bad object AFTER burning a paid VM + ~10 min'), and the remedy verbatim ('git push', with the fetch-refresh alternative and the board-edits-create-local-commits warning). Zero Hetzner calls made. Cleanup: git reset --soft HEAD~1 (empty commit, tree untouched — teammate in-flight work preserved). Log: tmp/statbus184-ac2-proof.log. Note the fix also proved itself against a REAL freshness race earlier today on the deploy path's sibling gate: local backlog auto-commits rode a deploy push and images-ready refused (recorded on STATBUS-194 comment #1) — the same genre this ticket closed for the harness. Both ACs checked; ticket Done.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The harness dispatch path refuses to run with an unpushed HEAD instead of burning a paid VM on a commit the VM cannot resolve. Fix shipped earlier at 347cc7e85 (re-check at the commit-pin point, closing the TOCTOU window against backlog auto-commits); proven 2026-07-20 by a deliberate run: an empty unpushed commit + a real dispatch produced the loud refusal naming the commit, the consequence, and the remedy (git push), with zero VMs created.
<!-- SECTION:FINAL_SUMMARY:END -->
