---
id: STATBUS-271
title: >-
  rc10-cut: the manifest and proving sequence for the next candidate —
  wedge-class fixes block, everything else rides
status: To Do
assignee: []
created_date: '2026-08-27 13:08'
updated_date: '2026-08-27 23:30'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 19:39
---
v2026.08.0-rc.11 CUT (2026-08-27 evening, tag at 5399acd8b) — this candidate supersedes rc.10 as the one riding the proving sequence, carrying everything the manifest demanded plus the evening's landings: 263 (task_cleanup foundation — the named rider, no longer drifting), 264/265/266 (the wedge class, blocking items — landed pre-rc.10), 269 amendment, 280 (Stage 8 opt-in), 288 (staleness gate consults the executing workflow — proven live in this very cut's preflight: both migration-coverage refusals covered-by-construction with CI runs cited), and the go-test determinism fix. Preflight passed end to end with zero local test runs demanded. Chain running under watch. The proving sequence continues unchanged from here: chain green on dev → human canary on Norway against the observation card → promotion gate (which refuses until Norway carries a completed upgrade at the candidate's commit) → stable → fleet follows → Ukraine (already live on rc.10, channel=stable) is OFFERED the stable and a human opts in. RECORDED UNPROVEN carries forward: 264's retry loop still awaits STATBUS-279's fault-injection arc.
---

author: foreman
created: 2026-08-27 23:30
---
RC.11 CHAIN VERDICT (orchestrator 33109334330, completed 2026-08-27 ~23:05Z): FOUR OF FIVE LEGS GREEN — both install/upgrade smokes (proving 280's Stage-8 fix on real VMs), leg 3 dev takes the candidate automatically (the canary topology zero-hands), leg 4 install-recovery dispatched — but LEG 5 (upgrade arc harness, run 33115731212) RED: 8 scenario failures of 35. Mechanic's triage: TWO STANDING (restore-broke-reattempt = 227's bootstrap class, red pre-rc.11; rollback-pair-terminal = 228 family, red pre-rc.11; nothing red-before is green-now) and SIX NEW AT RC.11 — cross-version-rename-handoff, postswap-container-restart-kill, postswap-mid-migration-kill, postswap-mid-tx-kill, transient-db-backoff, un-park-to-completion — sharing ONE signature: the upgrade row never reaches its terminal state ('expected completed/rolled_back, actual available'; '?' where a row value should be; 'no terminal state within 1800s'). One regression, six costumes — suspect list is rc.11's upgrade/worker-path delta (263's worker startup calls + two migrations the leading hypothesis: a version-B worker starting against a schema-A database calling functions that do not exist yet). Engineer diagnosing with the King's overnight mandate active: root-cause → fix → land → foreman cuts rc.12 → chain re-proves. rc.11 MAY NOT BE PROMOTED (its own guard said so: nothing may be promoted).
---
<!-- COMMENTS:END -->
