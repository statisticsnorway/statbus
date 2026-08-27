---
id: STATBUS-262
title: >-
  no-facets-stuck: no.statbus.org's Reports progress hangs at "Computing history
  facets 91%" — stuck for ages, worker derive pipeline suspected
status: To Do
assignee: []
created_date: '2026-08-27 12:35'
updated_date: '2026-08-27 12:46'
labels:
  - worker
  - production
  - norway
dependencies: []
priority: high
type: bug
ordinal: 255000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by the King 2026-08-27 with a screenshot of no.statbus.org: the Reports dropdown shows "Reports Progress — Handle ~1 legal units, ~1 enterprises — Computing history facets 91%" and has been sitting there "for ages".

no.statbus.org is the Norway box — the HUMAN CANARY (prerelease channel, deliberately installed candidates against an observation card), slot `no` on niue (offset 3). A hang on the human canary is exactly the kind of observation that box exists to produce: whatever candidate it runs may carry a worker defect that the chain-driven dev box did not surface.

"Computing history facets" is worker derive-pipeline territory (doc/derive-pipeline.md; structured concurrency per doc/worker-structured-concurrency.md — ONE top-level task per queue, top fiber blocks until all children complete). A progress stuck at 91% for a long period means a derive child task is hung, crash-looping, or dead with the parent still waiting — or the progress reporting itself is stale while work completed/failed underneath.

INVESTIGATION (read-only, via operator): worker.tasks state distribution, the non-completed tasks and their ages/errors, worker container status and log tail, and which version the box is running (it is the human canary — the candidate identity is part of the diagnosis).

Note the oddity in the banner itself: "~1 legal units, ~1 enterprises" — a tiny unit count with a facets computation that cannot finish suggests either a pathological task on trivial data (loop/deadlock rather than volume) or a progress denominator bug.

WHAT IS ACHIEVED: the hang is diagnosed to a named cause on a named version, the fix ships as code through the normal path, and the human canary's observation card gains whatever check would have caught this earlier.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 12:36
---
KING'S ADMIN-UI EVIDENCE (screenshots, no.statbus.org/admin/worker-tasks, 2026-08-27): task chain Recording changes #646207 → Deriving reports #646212 (waiting, serial) → children 646213 statistical history COMPLETED, 646214 history_reduce COMPLETED, 646215 search facets COMPLETED, 646216 merge search facets COMPLETED, 646217 Computing history facets WAITING (concurrent, 8.2s, "1280 children"), 646218 Merging history facets PENDING. Inside #646217: ALL 1280 `derive_statistical_history_facet_period` children COMPLETED (pages 1 and 26-of-26 both verified green, durations 400ms–1m30s, ~12k rows each), created 7 days ago.

READING: nothing is running and nothing is slow — every child is done and the parent never transitioned. A LOST WAKEUP: under structured concurrency a waiting parent with all children complete must complete and release the next serial task (the merge, still pending). The stuck "91%" is the pipeline fully done except the parent's own bookkeeping and the un-started merge.

HYPOTHESIS (labelled as such): 7 days ago ≈ 2026-08-20; if a candidate was deliberately installed on the human canary that day, the worker restarted mid-derive — children completed around the restart window, the parent's wake signal died with the old process, and resume-on-startup does not re-examine waiting parents whose children are ALL already complete. To confirm: operator's DB reads (exact states/timestamps of 646212/646217/646218 and last-child completion vs worker restart time in logs), then root-cause in the worker's resume path.
---

author: architect (pinned by foreman)
created: 2026-08-27 12:41
---
ROOT-CAUSE VERDICT (ranked; discriminating reads dispatched to the engineer). THE MACHINERY: STATBUS-163's backstop clearStaleReadOnlyWindow (service.go:3880) detects and clears a stale window — but it is called from Run() (:2388), BOOT ONLY, and returns early on three guards: flag present/unreadable; ANY in_progress row; any failed row with retained backup_path (STATBUS-209 ARM A abort hold).

H1 (favoured): a PARKED row — state='in_progress' forever by design — permanently disarms guard 2 on every boot. Fits all facts: both upgrade rows completed, box looks green, dev (no parked row) healthy on the same binary. Cross-mechanism coupling: park's forward-only state silently disarms a guard written for a different meaning of the same column.
H2 (NOT a defect — must be excluded before acting): a failed row with retained backup_path means the window is a DELIBERATE abort-hold protecting a possibly-broken volume until human-gated ./sb install replay; the only defect is that nobody was told for a week.
H3: the terminal OFF genuinely failed — the invariant log COMPLETION_READ_ONLY_WINDOW_LIFTED violated (:3391) would be in the journal.
The rc.08→rc.09 double-run is likely irrelevant — the differentiator is rune's ROW STATE, not sequencing.

DISCRIMINATING READS (engineer running): (1) SELECT id, state, recovery_parked_at, backup_path, error FROM public.upgrade WHERE state IN ('in_progress','failed'); (2) journal grep COMPLETION_READ_ONLY_WINDOW_LIFTED; (3) journal grep 'STATBUS-163 BACKSTOP' — absence across a week of boots is itself evidence.

REMEDY (if H1/H3): ./sb install on rune — no new code needed; the install ladder is ARM A's second invoker of the same backstop. NAMED CONSEQUENCE before anyone runs it: under H1, ./sb install is the deliberate un-park trigger — it grants the parked candidate one fresh attempt, a bigger action than "unstick the worker". If the reads show neither row nor invariant log, the shipped code cannot explain it and the architect designs the addition.

TWO LOUD GUARDS RULED: (1) the worker must FAIL ITS HEALTH CHECK when its writes are refused — alive-but-cannot-write is the zero-scope shape in a health-check costume; repeated 25006 went into a log nobody reads for a week. (2) completion must not be REPORTABLE while the window is on — today the invariant is asserted in a log line while the row says completed; the invariant should bind the state, not narrate it. task_cleanup split out as STATBUS-263.
---

author: architect (pinned by foreman)
created: 2026-08-27 12:46
---
RULING ON THE REVERSAL (2026-08-27): the engineer is right and my ranked hypotheses were wrong in every part — I built them on the brief's unverified premise (window still on) while the authoritative read was in flight to me. The window has been OFF the whole time; the backstop is correct at rc.09 and had nothing to fire on.

CONFIRMED AT SOURCE, AND WORSE THAN STATED: the worker starting inside the read-only window is NOT a race — it is the DESIGNED ORDER. service.go success path: :6931 healthCheck (services must be UP) → :6944 setMaintenance(false) → :7039 terminalExec(windowOffSQL). Same shape at :6395→:6401. Every upgrade starts the worker inside the window by construction; the exposure only does damage when abandoned 'processing' rows exist to reset.

THIS ANSWERS THE DOUBLE-UPGRADE QUESTION: rc.08 stopped the worker mid-derive and CREATED the four abandoned rows; rc.09's restart-inside-window then silently refused their startup-only recovery. One upgrade alone has no victims — the first manufactures the casualties, the second destroys the rescue mechanism. That is why rune wedged and dev (rc.09 alone) did not.

REMEDY RATIFIED, awaiting the King: `docker compose restart worker` on rune — the product's own recovery re-run outside the window; reset flips the four rows to 'interrupted', claimed at priority 0 ahead of pending; parent completes, merge runs. Explicitly NOT `./sb restart worker` (takes a profile — would bounce the whole box including the app).

STRUCTURAL FIX, RANKED: PRIMARY — the missing retry: a once-per-startup crash recovery that can fail and never run again converts ANY transient condition into a permanent wedge; fixing it closes the whole class. SECONDARY — the ordering, with a REAL TENSION that must be ruled, not assumed: clearing the window before the health check would clear it before the upgrade is known good, trading a wedge for a hole in the rollback guarantee. THIRD OPTION to argue when built: exempt the worker's startup recovery the way the upgrade's own writers self-exempt (system maintenance, reverted by rollback anyway) — but an exemption on an accident-guard must be argued, never slipped in.

THE GUARD: worker-health was the wrong place — the worker WAS healthy, every other queue ran for six days. The wedge's signature is A TASK IN 'processing' WITH NO LIVE CLAIMANT for longer than any plausible runtime — detectable, cheap, would have surfaced this in hours. And a failed startup crash-recovery must never be merely logged: it retries until success, or the worker refuses to report healthy. The King found this in a progress bar; that is the finding.
---

author: engineer (pinned by foreman)
created: 2026-08-27 12:46
---
DISCRIMINATING READS COMPLETE — all three original hypotheses REFUTED by direct evidence, closing the chain on the ratified root cause. H1: zero rows in state in_progress/failed (19 superseded, 13 completed — no parked row exists). H2: zero failed rows, no retained backup_path — no hold to be silent about. H3 inverted: COMPLETION_READ_ONLY_WINDOW_LIFTED prints ONLY inside if werr != nil (service.go:3389-3396), so its journal absence proves the flip SUCCEEDED; catalog agrees (off).

Journal detail defused before anyone re-raises it: 'read-only window ON' appears twice with no OFF line — expected, the Printf lives in setDatabaseReadOnly which only failure paths call; the success path is terminalExec(windowOffSQL), silent when it works. Two silences that both mean healthy.

Timing exact: worker StartedAt 2026-08-21T18:23:15.955Z, RestartCount=0; first refusal 18:23:16.263 (+0.3s, the startup crash-recovery call); window lifted +2.4s. The reset has run EXACTLY ONCE, inside the window, never again — no later restart, and connection inheritance is dead as a cause (daily maintenance tasks completed 22nd-26th prove the worker's sessions write fine; only the four rows were never reset).

Root cause final: upgrade restarts the worker BEFORE clearing its own window (designed order); the once-per-startup recovery lands in the 2.4s gap, is refused, logged at ERROR, abandoned; neither side retries. Remedy before the King: docker compose restart worker on rune.
---
<!-- COMMENTS:END -->
