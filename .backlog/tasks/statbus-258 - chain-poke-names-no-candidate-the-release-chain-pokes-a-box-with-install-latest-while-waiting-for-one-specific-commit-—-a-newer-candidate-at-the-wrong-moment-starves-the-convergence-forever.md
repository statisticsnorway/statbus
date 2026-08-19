---
id: STATBUS-258
title: >-
  chain-poke-names-no-candidate: the release chain pokes a box with "install
  latest" while waiting for one specific commit — a newer candidate at the wrong
  moment starves the convergence forever
status: To Do
assignee: []
created_date: '2026-08-19 19:14'
labels:
  - release
  - upgrade
dependencies: []
priority: medium
type: bug
ordinal: 251000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The dev-canary leg of the release chain (STATBUS-247, landed with C1 4324f1d3a) points dev's deploy branch at the candidate's commit and pokes the box via `./sb upgrade apply-latest` — but apply-latest resolves THE LATEST tag on the channel, not the commit the chain just pushed. If a newer RC exists at that moment (two cuts in flight, or a fix release tagged during the window), the box installs the newer one while the chain polls for convergence on the older one — and the convergence never arrives. The chain then reds (or hangs) on a box that is actually healthy and newer than requested.

Same defect family as STATBUS-256: a mechanism addressing "latest" where the contract is a SPECIFIC candidate. The architect flagged it during the 2026-08-19 dev-down incident review; it cannot bite on the first cut (the pushed candidate IS the newest) but becomes live the first time two candidates overlap.

THE FIX SHAPE (to be designed, not assumed): the poke should carry the candidate identity (commit SHA per canonical-commit-naming) and the box should install exactly that — register+schedule of a named target, not apply-latest — OR the chain's convergence check should accept "box is at the poked commit OR a descendant candidate on the same channel" with the reason logged. The first shape is preferred (candidate-addressed, matching STATBUS-244's ruling that only named candidates reach installations).

WHAT IS ACHIEVED: the chain's convergence poll can never be starved by a concurrent newer candidate, and a box never installs something other than what the chain believes it is testing.
<!-- SECTION:DESCRIPTION:END -->
