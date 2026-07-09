---
id: STATBUS-154
title: >-
  park-write-teardown-race: the park terminal's DB write can fail on the
  daemon's own canceled context — process exits parked, row says not parked
status: In Progress
assignee:
  - engineer
created_date: '2026-07-09 00:48'
updated_date: '2026-07-09 02:32'
labels:
  - product
  - upgrade
  - recovery
  - install-recovery
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - test/install-recovery/arcs/postswap-health-park-arc.sh
  - STATBUS-148
  - STATBUS-147
priority: high
ordinal: 155000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a park is a park — the process outcome and the database row never disagree; the operator's re-trigger surface (recovery_parked_at) is trustworthy at exactly the moment a headless box depends on it.
> STAGE: Stage 1 product finding — campaign finding #7, caught by the health-park arc's re-park assert on wave 5 (run 28984873852, base b4df4bff2).
> COMPLEXITY: architect rules the fix shape; likely engineer-scoped (terminal-write path must not share the dying pass's context).

OBSERVED (job log, health-park arc, 2026-07-09): the un-park→re-park leg ran; the fresh attempt genuinely re-parked — the install's stderr printed the full park error ("parked on deterministic forward failure: HEALTHCHECK_REST_DOWN ... fix the cause, then re-trigger") and exited 1 — but the arc's assert then read recovery_parked_at IS NULL ("✗ expected recovery_parked_at IS NOT NULL after the fresh attempt re-parks, got parked=f"). The daemon journal names the mechanism, twice, in two forms:
- 00:33:55: "Error: recover from flag: park deterministic forward failure for upgrade 2: conn closed"
- 00:38:18: "Error: recover from flag: resumePostSwap: park write failed for upgrade 2: failed to deallocate cached statement(s): timeout: context already done: context canceled"
Both passes exited status=1 (systemd Failed with result 'exit-code') AFTER failing to persist the park row. The STATBUS-149 negative oracle held in the same logs (zero advisory-holder terminations), so this is NOT the session reaper killing the connection — the park write races the daemon's OWN pass teardown (context canceled / connection closed while the terminal write is in flight).

IMPACT: a parked box whose row does not say parked — the operator's legend/forecast, the service's parked-skip boot, and the re-trigger workflow all key on the row. In the field this is a box that keeps re-attempting (and re-failing) instead of sitting stably parked, or an operator told nothing is parked when the log says otherwise. The arc's red is correct and stays red until this is fixed.

EVIDENCE: tmp/wave5-healthpark-job.log lines 4708 (harness rc=1 at arc :408), 4789-4795 (re-park stderr + parked=f assert), 5233-5235, 5311-5313, 5395-5397 (journal); artifact upgrade-arc-log-postswap-health-park-28984873852.zip.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The park terminal write survives its pass's teardown: the write path does not depend on a context/connection that the exiting pass is simultaneously canceling (fix shape architect-ruled)
- [x] #2 Process outcome and row state cannot diverge: exiting as-parked REQUIRES the row write to have landed (or the exit path escalates loudly, never silently)
- [ ] #3 Oracle: the health-park arc's un-park→re-park leg goes green — recovery_parked_at set after the fresh attempt re-parks
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-09 00:53
---
RULED (architect, 2026-07-09), engineer building. THE SHAPE: one teardown-immune terminal-write helper used by EVERY state-terminal writer (parkUpgrade, writeRollbackTerminal, the completed UPDATE, restoreAndFinalize's terminal — the 111 extraction made them shared machinery, exactly why the scope is all-of-them). Three properties: (i) never the pass context — context.Background + own ~30s deadline (a terminal write is the pass's last word and must not die with the pass); (ii) a fresh short-lived daemon-tagged connection per write (149's recoveryDSN), never the pass's queryConn — always-fresh sidesteps the cached-statement class entirely; (iii) bounded retry, generalizing the existing 047-H completion-write reconnect save (the house precedent that this class was known and patched at ONE terminal — 154 proves it needed all of them); idempotent by construction via parked_at-IS-NULL and state-guarded UPDATEs. EXIT INVARIANT: exiting as-terminal REQUIRES the write landed; on failure after retries, escalate loudly naming the divergence (row stays in_progress, next pass re-evaluates) — today's degraded behavior made honest. recordInProgressFailure stays best-effort (narrative, not state). Tests: helper + four call-site swaps + canceled-parent-ctx unit test. Oracle: the health-park arc re-run — the un-park→re-park leg landing recovery_parked_at is the exact assert that caught this.
---

author: foreman
created: 2026-07-09 01:12
---
SHIPPED in a4589c6d9 (dual-reviewed: architect ship zero changes; foreman first-hand). terminalUpdate carries all three ruled properties (Background+own deadline; fresh daemon-tagged conn per attempt via 149's recoveryDSN — cached-statement class structurally unreachable; bounded retry, callers own escalation). All four writer families swapped; the old bespoke 047-H retry ladders DELETED (clean break — precedent absorbed, not duplicated); writeRollbackTerminal's ctx param dropped (PIN-i structural). Park keeps siren-once through the verify-read resolving the ambiguous 0-rows case on the same immune primitive; exit-as-terminal requires the landed write everywhere, else the loud row-stays-in_progress escalation. Tests: structural pins (Background+recoveryDSN, not queryConn) + the canceled-parent-ctx behavioral proof. AC#1/#2 checked. AC#3 rides wave 6 (health-park re-run on a4589c6d9): the un-park→re-park leg landing recovery_parked_at — the exact assert that caught this.
---

author: foreman
created: 2026-07-09 01:53
---
WAVE-6 FIRST-CONTACT REGRESSION, diagnosed by the fix's own design (run 28987136404 on a4589c6d9): the first park never landed in 1200s — terminalUpdate's FRESH session inherits the post-swap read-only window, and 'cannot execute UPDATE in a read-only transaction' (25006) is non-conn so the helper correctly returned it without retry. The journal named it three times via the new loud escalation ('park write failed (id=2) ... the row stays in_progress and the next pass re-evaluates') — no wrong terminal written, the row honestly in_progress: the exit invariant worked while the implementation was wrong. The old pass-conn wrote through the window because its session PREDATED the read-only flip — the established machinery-writes-through semantic, not luck (the window is an accident-guard against application writes, doc-021/110). RULED PATCH (architect): session-level SET default_transaction_read_only = off inside terminalUpdate right after connect (userset GUC — no privilege needed, consistent with accident-guard-not-hard-lock); DSN -c rejected (over-broad — flips everything on recoveryDSN); BEGIN READ WRITE rejected (choreography for no gain); rowIsParked rides the same helper unchanged. NAMED RESIDUAL, pre-existing, not tonight's patch: the same class exists latently on the daemon's MAIN conns — a mid-window reconnect() of queryConn would inherit read-only and break in-window machinery writes (recordInProgressFailure, the backup_path record) identically; now LOUD if it fires thanks to the 154 escalations — a future 25006 in the journal is this sibling, recognizable in seconds. Engineer patching; wave 7 is the oracle.
---

author: foreman
created: 2026-07-09 02:32
---
WAVE-7 BOUNDED TRACE (engineer, 2026-07-09 02:30): DID NOT CLOSE — stopped at the bound per ruling, no fix shipped, no writer convicted. What it established: full state-writer enumeration recorded (13 sites: claims :1570/:4438, supersede :1404/:3942, completed :2877/:5579/:6104/:2945/install.go:2363, failed :2654/:6886/:7164/:2776/:6538, scheduled :4044/:4226, available :4584). BOTH SUSPECTS CLEARED WITH EVIDENCE: (a) the self-heal canary never fired (every boot logged 'NOT self-healing; deferring' — lines 4751/5233/5266) and applyPostSwap's own health failed 5× in the un-park attempt — NO completion of row 2 exists anywhere in the journal (all completed-markers grep empty); (b) UnparkByID/recoveryBudgetResetCols touches only attempts+parked columns, never state; also cleared: reschedule ('already scheduled or in progress — no action needed', :5059). THE PUZZLE: at re-park, state != in_progress AND parked_at IS NULL and the row exists — yet no state write to row 2 appears in the captured journal; the writer is invisible (unlogged path, or a boot the journal doesn't narrate). LATENT FINDING carried (not the convicted cause): none of the three completed-writes clears recovery_parked_at — a completion landing over a parked row leaves completed+parked_at, which RecoveryBudgetGuard reads as PARKED, un-park clears, re-park hits exactly 'not parkable'; same signature, worth checking against the next dump. MORNING PLAN: the row-state dump rider is in (653834672) — the next red captures state verbatim; the engineer's instrumentation recommendation stands for ruling: one log line on EVERY state write (id, old→new) — the honest park arm sees the symptom, the writer log would name the writer.
---
<!-- COMMENTS:END -->
