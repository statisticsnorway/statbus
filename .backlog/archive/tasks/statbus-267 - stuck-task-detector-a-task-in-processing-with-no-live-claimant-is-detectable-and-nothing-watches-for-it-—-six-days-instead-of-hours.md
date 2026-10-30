---
id: STATBUS-267
title: >-
  stuck-task-detector: a task in processing with no live claimant is detectable
  and nothing watches for it — six days instead of hours
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-27 12:49'
updated_date: '2026-08-27 21:51'
labels:
  - worker
dependencies: []
priority: medium
type: enhancement
ordinal: 260000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-262: four tasks sat in 'processing' with no live claimant for six days on a box that looked healthy — the worker ran every other queue, the upgrade reported completed, and the wedge was found by the King in a progress bar. Worker-health was the wrong place to look, because the worker WAS healthy.

Architect's ruling: the wedge's signature is A TASK IN 'processing' WITH NO LIVE CLAIMANT for longer than any plausible runtime — detectable, cheap, and it would have surfaced this in hours. Build the detector as a loud guard (per the two-tier discipline: this is a warning surface, not a silent self-heal — detection reports loudly; any automatic remediation is a separate argued decision, see feedback rule "no standing self-heal paths").

Design questions for the architect at build time: where it runs (worker maintenance loop vs admin UI vs both), what "plausible runtime" means per command class, and how it reports (the admin worker-tasks UI already renders states — a stuck-processing badge there reaches the human who looks).

WHAT IS ACHIEVED: an orphaned processing task is a loud finding within hours, not a silent wedge found by a human staring at a frozen progress bar.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-27 16:12
---
DESIGN (2026-08-27). TWO SIGNALS, ship the first alone: (1) EXACT, no tuning — a task in 'processing' whose start PREDATES the current worker instance's start is abandoned by definition; it is reset_abandoned_processing_tasks()'s own condition evaluated periodically instead of only at startup, so its presence means precisely "the startup reset did not run or failed" — the rune signature. Zero false positives, no per-command table. (2) HEURISTIC, separate judgement, do not let it delay (1): a live-worker task far beyond its command's observed norm — thresholds derived from worker.tasks' own completed-duration history per command (hand-maintained tables rot silently); no-history commands use a generous ceiling AND say so.

WHERE: the worker's MAINTENANCE queue — during the rune wedge the maintenance queue ran every day, and its continued health is exactly what made the wedge invisible; put the detector in the thing that stayed healthy and the mechanism that hid the problem becomes the one that reports it.

HOW IT REPORTS: loudly, and deliberately NOT through container health — health-check wiring would auto-restart the worker, re-run the reset, and quietly fix it: the standing self-heal the King forbids. A condition that should never occur surfaces to a HUMAN: loudest log level, visible where an operator reads status, restart left to a person. Composes with 264: if they restart and the reset still fails, retry-then-FATAL makes it a visible crash-loop.

The reproduction arc is deliberately NOT here — filed as STATBUS-279, the named path to 264's proof. Builder: engineer (Crystal worker territory), queued behind STATBUS-263.
---

author: foreman
created: 2026-08-27 17:38
---
NEIGHBOURHOOD REFINEMENT deferred here from 263's landing review (architect, non-blocking): 096 Property 1b's index-pairing assertion matches indexdef LIKE '%'||command||'%', so a future recurring command whose name is a SUBSTRING of an already-indexed one (e.g. a hypothetical job_cleanup vs idx_tasks_import_job_cleanup_dedup) would match the wrong index and report t with no index of its own. One-line tightening (anchor the match, e.g. on the WHERE command='<name>' predicate text) when this file is next opened for 267's build.
---

author: engineer
created: 2026-08-27 21:44
---
**BUILT AND FROZEN — signal (1) alone, both arms RED-verified. One correction to the ruling's wording, proven rather than argued.**

## The correction, and why it matters

The ruling says to use "reset_abandoned_processing_tasks()'s own condition evaluated periodically". **Read literally that condition is `state = 'processing'` and nothing else** — the function resets every processing row unconditionally, which is CORRECT there because it runs only at startup, when no task can legitimately be processing.

Evaluated periodically it would flag **every running task on a busy box** — a 100% false-positive detector, the exact opposite of the ruling's own "zero false positives" requirement.

So I implemented the ruling's INTENT, which its first sentence states exactly: *no live claimant*. A task claims a backend by writing `worker_pid = pg_backend_pid()`, so a `processing` row whose claiming backend is gone is abandoned by definition — no threshold, no per-command table. **RED ARM B below proves the literal reading would have fired on a healthy row.**

## The predicate

`worker.abandoned_processing_tasks()` — processing rows whose `worker_pid` has no matching live backend in `pg_stat_activity` for this database.

One judgement recorded at the line: liveness matches on **pid + database only, NOT also `application_name = 'worker'`**. The stricter form would report a RUNNING task as abandoned if a worker backend ever failed to set its application_name; the looser form's cost is the reverse — a recycled pid could mask one abandoned task, delaying a report that recurs daily anyway. **Given a choice between a missed detection and a false alarm at the loudest level, the false alarm is worse: it trains operators to ignore the one message meant to be unignorable.**

## How it reports

WARNING (reaches the log, survives the abort) **and** EXCEPTION (reddens the task, which is what an operator reads in worker.tasks / the admin UI). Deliberately NOT wired to container health — that would restart the worker, the startup reset would clear the rows, and the wedge would silently repair itself: the standing self-heal the King forbids. The message says outright that it is *not* a failure of the check, names the ids, and tells the human to inspect before restarting.

Because recurrence belongs to the runner (STATBUS-263), **a red run does not silence the detector** — it runs again tomorrow and says so again. It rides the registry mechanism (`schedule_interval` + a registered command on the maintenance queue) rather than a hand-rolled timer, exactly as instructed — and the maintenance queue is the thing that stayed healthy through the rune wedge, so the mechanism that hid the problem now reports it.

## Tests — 097, both arms, RED-verified

`ok 4 - 097_stuck_task_detector`; all four worker tests green together (094, 095, 096, 097). Green **twice in a row** before I believed it, after the first attempt exposed nondeterminism (the handler's message embeds `process_start_at`); fixed by pinning both the timestamp AND `TimeZone = 'UTC'`, since timestamptz renders per session zone and an expected file generated here would otherwise diff on a CI runner elsewhere.

RED via transactional function replacement (`tmp/red_verify_267.sql/.log`), the technique accepted for 263:

| arm | mutation | result |
|---|---|---|
| LOUD | predicate blinded | detected 1 → **0**, handler silent where the test demands a raise |
| SILENT | liveness check removed | false positives 0 → **1**, handler **RAISES on a perfectly healthy row** |

Restored, nothing committed.

## Also done: the deferred 096 tightening (comment #2)

Property 1b's index match is now anchored on the index's WHERE predicate (`(command = 'x'::text)`) instead of the name appearing anywhere — a future `job_cleanup` would no longer match `idx_tasks_import_job_cleanup_dedup` and report `t` with no index of its own. Regenerated and green. **The new command is automatically covered by that pairing test**, which is why it ships with its own dedup index.

## Files — 9

migrations `20260827213834_...up.sql` / `.down.sql` (terminators present on both — 263's cautionary tale); `doc/db/function/worker_abandoned_processing_tasks().md`, `doc/db/function/worker_command_detect_stuck_tasks(jsonb, jsonb).md`, `doc/db/table/worker_tasks.md`; `test/sql/097_...sql` + expected; `test/sql/096_...sql` + expected.

Signal (2) NOT built, as ruled.
---

author: foreman
created: 2026-08-27 21:51
---
LANDED at 4e55c2dd2 (9 files, 503 insertions) after the architect's LAND with the engineer's RULING CORRECTION verified by mechanism: the ruling's literal condition (reset_abandoned's state='processing') is safe at startup ONLY because a preceding application_name='worker' termination clears live claimants — evaluated periodically it flags every healthy in-flight row; the built detector instead uses the codebase's own claim idiom (worker_pid = pg_backend_pid(), five handler precedents) with pg_stat_activity liveness — zero thresholds, and RED arm B DEMONSTRATED the literal reading raising on a healthy row. CONVERGENCE recorded on both tickets: 267 and 282 independently arrived at 'the postmaster is the authority on live claimants'. The liveness looseness (pid+db, not app_name) carries the architect's stronger argument AND its coupling at the line: LICENSED BY RECURRENCE — a pid-reuse false negative self-corrects at tomorrow's run, an EXCEPTION-level false alarm never decays; one-shot-ifying the detector must revisit the choice. Signal (2) (duration heuristics) deliberately NOT built, per the ruling. Also in the unit: 096 Property 1b re-anchored on the index WHERE-predicate (the substring corner closed), and the pairing test caught its FIRST REAL MEMBER — detect_stuck_tasks could not join the recurring family without shipping its dedup index. Known accepted divergence: doc/db's dump of one function carries pre-amendment comment prose (doc/db generates from the SEED; the amendment was applied post-seeding; executable SQL measured IDENTICAL 11/11 lines) — self-corrects at the next seed rebuild; the general mechanism is ticketed separately. Rides the next candidate.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The rune wedge's second half is closed: an orphaned processing task is now a loud finding within a day instead of a six-day silence found by a human staring at a frozen progress bar. The detector runs daily from the worker's own maintenance queue — the thing that stayed healthy through the wedge becomes the thing that reports it — and its signal is exact: a processing row whose claiming backend is gone from pg_stat_activity is abandoned by definition, zero thresholds, no per-command tables. It reports on two surfaces (a WARNING that survives the abort, an EXCEPTION that reddens the task) and is deliberately not wired to container health, because an auto-restart would silently repair the exact condition the message exists to surface. The build corrected the ruling's letter with proof (the literal condition would have been a 100%-false-positive detector), converged independently with 282 on the postmaster-as-authority principle, and exercised 263's recurrence registry as its first real member. Landed at 4e55c2dd2; rides the next candidate.
<!-- SECTION:FINAL_SUMMARY:END -->
