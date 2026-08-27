---
id: STATBUS-267
title: >-
  stuck-task-detector: a task in processing with no live claimant is detectable
  and nothing watches for it — six days instead of hours
status: To Do
assignee: []
created_date: '2026-08-27 12:49'
updated_date: '2026-08-27 17:38'
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
<!-- COMMENTS:END -->
