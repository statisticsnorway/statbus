---
id: STATBUS-300
title: >-
  arc-assert-patience: un-park's single-shot assert query reds the arc on one
  transient beat — the poll retries, the assertion does not
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-28 13:15'
updated_date: '2026-08-28 13:17'
labels:
  - install-recovery
  - testing
dependencies: []
priority: medium
type: bug
ordinal: 293000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an assertion that a state exists must be at least as patient as the polling that found it. In un-park-to-completion, the poll retries for a budget and the assertion one line later gets a single ungoverned shot — so one transient beat reds an arc whose product behavior was correct end to end.

WHAT HAPPENED (rc.15 fleet run 33163032285, job 98822622353; journal-first diagnostics confirmed working): the harness's own polling loop SUCCEEDED reading the parked row ("B parked (t+27s): 2|in_progress|t|disk nearly full..." — full state, id, reason), then the very next step, "assert park" (un-park-to-completion-arc.sh:359 via :354), calls the SAME row_cols_for function EXACTLY ONCE — a single SSH+psql call whose only guard is `|| echo "?|?|?|(db-down)"`. That sentinel is exactly what the failure captured ("id=? state=? reason=(db-down)"): one transient SSH/db beat, one query after an identical successful one, with zero retry budget at this one call site. Plausibly self-inflicted by the scenario's own disk-fill technique (~4GB free at that moment).

THE DAEMON WAS INNOCENT THROUGHOUT: no panic, no SIGABRT, no 294 signature anywhere in the journal; it un-parked and resumed the identical row minutes later. Classification: harness-side, not a product regression — but the red still cost a candidate's fleet a clean verdict.

FIX, mechanical (design complete): the assert-park read reuses the polling loop's own retry shape (same function, same 5s cadence, a short bounded budget — it asserts a state already observed, so the budget can be small); a sentinel answer inside the budget keeps retrying, a sentinel at budget-end fails with the last real read quoted alongside. Sweep the same file for OTHER single-shot row_cols_for calls with the sentinel fallback and give them the same treatment if any exist.

NOTED, not scope: the 400-line journal tail was eaten by two verbose restart cycles and repeated discovery-inactive blocks, so the park moment itself scrolled out before diagnostics fired — worth widening (or since-timestamp capture) as a future 296-family improvement; recorded here so the observation is not lost.

WHAT IS ACHIEVED: a transient beat cannot red an arc whose product behavior was correct, and assertions inherit the patience of the polls they follow.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic (pinned by foreman)
created: 2026-08-28 13:17
---
RE-TRIAGE WITH THE 299 FINGERPRINT TEST, explicitly negative: zero occurrences of Watchdog timeout / SIGABRT / SIGSEGV / Killing process anywhere in the job log — NOT 299's mechanism, no crash of any kind. AND THE DETAIL THAT SHARPENS THIS TICKET: the diagnostics-time db error was 'the database system is shutting down' — PostgreSQL's ORDERLY-STOP message — because at teardown the daemon was still alive and correctly MID-UPGRADE (read-only window engaged at 12:37:06, listen-loop stopped, progressing toward backup/swap): the harness's single-shot assert had already failed at ~12:36 and its EXIT trap reaped a VM that was demonstrably working toward legitimate completion. The row never reached terminal state because the test infrastructure ended the VM's life first, not because anything broke. The daemon's full arc — park → re-claim → resume → progress — was correct as far as it was allowed to run.
---
<!-- COMMENTS:END -->
