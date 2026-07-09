---
id: STATBUS-154
title: >-
  park-write-teardown-race: the park terminal's DB write can fail on the
  daemon's own canceled context — process exits parked, row says not parked
status: To Do
assignee: []
created_date: '2026-07-09 00:48'
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
- [ ] #1 The park terminal write survives its pass's teardown: the write path does not depend on a context/connection that the exiting pass is simultaneously canceling (fix shape architect-ruled)
- [ ] #2 Process outcome and row state cannot diverge: exiting as-parked REQUIRES the row write to have landed (or the exit path escalates loudly, never silently)
- [ ] #3 Oracle: the health-park arc's un-park→re-park leg goes green — recovery_parked_at set after the fresh attempt re-parks
<!-- AC:END -->
