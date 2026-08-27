---
id: STATBUS-271
title: >-
  rc10-cut: the manifest and proving sequence for the next candidate —
  wedge-class fixes block, everything else rides
status: To Do
assignee: []
created_date: '2026-08-27 13:08'
labels:
  - release
dependencies: []
priority: high
type: task
ordinal: 264000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King's directive (2026-08-27): cut the next candidate as soon as ready; a stable release follows (Ukraine + the fleet wait on it). Architect's ruled manifest, criterion = "does it close the wedge class":

BLOCKING: STATBUS-264 + 265, landed TOGETHER or 265 FIRST — 264 alone would crash-loop a worker on a box legitimately holding the deliberate abort-hold read-only state (STATBUS-209 ARM A); 265's exemption dissolves that. Also blocking by sequencing: the 259 ENDGAME lands BEFORE THE CUT (not merely before the chain run — the cut triggers the chain immediately, and without the endgame rc.10 proves the obsolete transport and wastes a cut).

RIDES: 263 (task_cleanup FK — real bug, not the class; named as riding so it stops drifting as it has since May). 267 (stuck-task detector — detects wedges, doesn't prevent them; FIRST in the queue behind stable, the fleet is about to double). Nothing else on the board is release-blocking.

PROVING SEQUENCE TO STABLE: rune verified un-wedged (remedy RAN 2026-08-27 ~12:56Z — four tasks re-ran, parent completed, merge started; final drain confirmation pending) → rc.10 cut → chain run proves the NEW transport zero-hands on dev (closes 246/247/249/252 legs + 261's pending-arm) → human canary on no AGAINST doc-035's observation card, deviations become tickets before promotion (247 AC#7) → promote to stable — and the promotion gate ENFORCES this: it refuses until Norway carries a completed upgrade at the candidate's commit (247 AC#11), so the human step cannot be skipped under pressure → fleet follows NON-UNIFORMLY: demo auto-applies if 248's trigger is built; country boxes are OFFERED and a human opts in → Ukraine installs the stable (STATBUS-268).

RECORDED UNPROVEN, deliberately: 264's retry loop — once 265 lands the reset is exempt and never refused, so NO normal upgrade exercises the retry; its proof waits on STATBUS-270's spec suite or deliberate fault injection. Written down so rc.10's green is never read as covering it.
<!-- SECTION:DESCRIPTION:END -->
