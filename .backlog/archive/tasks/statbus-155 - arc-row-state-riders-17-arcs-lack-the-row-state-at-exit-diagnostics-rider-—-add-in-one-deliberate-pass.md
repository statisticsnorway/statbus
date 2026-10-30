---
id: STATBUS-155
title: >-
  arc-row-state-riders: 17 arcs lack the row-state-at-exit diagnostics rider —
  add in one deliberate pass
status: Done
assignee:
  - mechanic
created_date: '2026-07-09 02:28'
updated_date: '2026-07-12 01:47'
labels:
  - install-recovery
  - tooling
dependencies: []
references:
  - test/install-recovery/arcs/
  - STATBUS-154
priority: low
ordinal: 156000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every arc's failure autopsy captures the upgrade row's state columns at exit — no future red requires hand-tracing a row's state from raw logs.
> STAGE: harness quality. FOUND: the wave-6/7 health-park autopsies (2026-07-09) traced row 2's state by hand twice because the diagnostics never queried it; the mechanic's sweep then enumerated the gap across the whole arc suite.
> COMPLEXITY: mechanic-simple, one deliberate pass (deferred from the overnight session — no midnight bulk edit).

THE RIDER (pattern already in postswap-mid-migration-kill-arc.sh, postswap-mid-tx-kill-arc.sh, and as of 653834672 postswap-health-park-arc.sh): in the arc's failure-diagnostics trap, dump the flag file + SELECT the upgrade row by commit_sha = B_FULL ORDER BY id DESC LIMIT 1 (the row is B's by construction — never the id=1 install row) with the state columns relevant to the arc's story (id, state, recovery_attempts, parked, reason, error as a good default set).

ARCS LACKING IT (mechanic's sweep, 2026-07-09): after-commit-before-recorded-kill, claim-without-notify, failing, postswap-after-commit-kill, postswap-between-migrations-kill, postswap-container-restart-kill, postswap-migration-ceiling, postswap-migration-oom, postswap-migration-timeout, postswap-rollback-restore-watchdog, postswap-watchdog-reconnect, preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill, rollback-kill, rollback-pair-terminal, working. The shared lib helpers (dump_daemon_state, dump_signing_diagnostics) are correctly scoped and unaffected — this is per-arc by design.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every arc in test/install-recovery/arcs/ carries the row-state-at-exit rider in its failure diagnostics, selected by commit_sha (never a hardcoded id)
- [x] #2 shellcheck baseline unchanged across the pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED cb0447893 (2026-07-12): the row-state-at-exit rider added to all 17 remaining arcs (17 files, +469/−17) — every arc's failure trap now dumps B's progress log, the daemon journal tail, the flag file, and the upgrade row's state columns selected by commit_sha (never a hardcoded id), running BEFORE any local cleanup and best-effort throughout so diagnostics can never mask the triggering assertion. Two deliberate adaptations recorded: failing-arc queries commit_sha IN (B,C) with id ordering (both phases actively driven — a red can land in either); working-arc stays B-only (its C-leg is currently skipped, no row exists). Unit-variable choice verified per file. AC#2 held by a per-finding shellcheck comparison against HEAD (identical SC codes + messages, only line shifts) + bash -n on all 17. Review: architect SHIP as-built (sampled both adaptations in full + a bulk representative; rc≠0 gating, dump-before-cleanup ordering, and the ARC_UPGRADE_UNIT global all verified). The capability that produced the wave-9 dumps convicting the 154 invisible writer is now standard on every arc. Future note (mechanic + architect concur): upgrade_state_log dumps stay health-park-specific — none of these 17 exercises a multi-writer race today; revisit if one gains a displacement/un-park leg.
<!-- SECTION:FINAL_SUMMARY:END -->
