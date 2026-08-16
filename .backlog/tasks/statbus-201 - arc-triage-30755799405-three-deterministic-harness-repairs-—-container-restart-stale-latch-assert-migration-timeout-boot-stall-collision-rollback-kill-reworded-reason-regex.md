---
id: STATBUS-201
title: >-
  arc-triage-30755799405: three deterministic harness repairs —
  container-restart stale latch assert, migration-timeout boot-stall collision,
  rollback-kill reworded-reason regex
status: To Do
assignee: []
created_date: '2026-08-02 19:10'
labels:
  - install-recovery
  - upgrade
  - testing-foundation
  - triage
dependencies: []
references:
  - test/install-recovery/arcs/postswap-container-restart-kill-arc.sh
  - test/install-recovery/arcs/postswap-migration-timeout-arc.sh
  - test/install-recovery/arcs/rollback-kill-arc.sh
  - cli/internal/migrate/migrate.go
  - cli/internal/inject/inject.go
priority: high
ordinal: 201000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every arc asserts the CURRENT ratified contract; a red means the product broke, never that the arc aged.
> FOUND: 2026-08-02, architect triage of the cut-candidate suite (run 30755799405, 32 green / 4 red at 2ab6126a1). These three reds are harness debt — the product behaved per ratified doctrine in all three; evidence per arc below. (The fourth red is the STATBUS-200 product defect.) None of the three post-gate diffs (a316b1a2b heartbeat, 337cb48e9 caddy-404, b39bbf347 log floor) is implicated in these three; registry weather implicated in none.

1. postswap-container-restart-kill-arc — STALE ASSERT (pre-039/pre-192 doctrine). The kill after container-start converged FORWARD: journal shows "the database is already at the new version — continuing forward, not rolling back" → "resumeNewSb: containers healthy at aa1c302d, no pending migrations — self-healing row 2 to completed" → [completed-self-heal]. That is exactly the serve-proven contract (STATBUS-160/192/193) the docs now carry; the arc demands the retired "Resuming one-shot latch → rollback" and cites ancient service.go:755. FIX: re-anchor the terminal assert to serve-proven convergence — state=completed via [completed-self-heal], flag absent, data intact, NRestarts bounded; drop the rollback demand. Cross-reference postswap-converged-selfheal-arc (adjacent window, deliberately proves the same class).

2. postswap-migration-timeout-arc — BOOT-STALL COLLISION, deterministic. Since STATBUS-116 (98093f69f, 2026-07-03) post_restore fixups run through runPsqlFile on EVERY migrate-up ("always runs", migrate.go:1169-1183), and the stall marker migration-slower-than-systemd-unit-timeout sits inside runPsqlFile (migrate.go:537). The arc arms the stall via unit env + restart, so the daemon's OWN BOOT stalls at the fixups (journal: "Running post-restore fixups..." → INJECT stall at 17:38:57, before listenLoop) — the scheduled row can never be claimed (300s timeout, row stays 'scheduled'). The 195 heartbeat is exonerated: discovery completed in seconds (NOTIFY 17:38:25 → images verified 17:38:40). FIX: add a DELTA-scoped stall marker at applyNewSbUpgrading's migrate invocation (an inject-vocabulary ADDITION — permitted; thinning forbidden), re-anchor the arc to it; the generic runPsqlFile marker stays for its other users.

3. rollback-kill-arc — REWORDED-REASON REGEX. The arc (assert added a64ce8f6d, 2026-06-19) pins "pre-swap, before binary-swap commit boundary"; the King's plain-vocabulary reword (6c90e2964, 2026-07-07) changed the emitted wording to "before booting the new binary — the point of no return" (service.go:1284). The product route and terminal are exactly as contracted (rolled_back, recovery_attempts=2, pre-swap classification, backup identity honest). FIX: regex → a stable fragment of the ratified wording ("before booting the new binary") alongside the INSTALL_PRECONDITION_FAILED token.

NOTE FOR THE RECORD: all three arcs were last green BEFORE the code changes that aged them (July 3 / July 7 / the 192-193 serve-proven landing) — today's suite was their first exercise since. The STATBUS-196 drift gate covers code↔diagram drift; code↔ARC-assert drift has no gate — worth a future thought, not this ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 postswap-container-restart-kill-arc asserts the serve-proven convergence contract and is green on a real VM
- [ ] #2 postswap-migration-timeout-arc stalls ONLY the delta migrate via a new delta-scoped inject marker and is green on a real VM; the daemon boot with the env armed reaches its main loop
- [ ] #3 rollback-kill-arc matches the ratified plain-vocabulary reason and is green on a real VM
- [ ] #4 The inject-marker addition is registered in inject.go with the naming discipline; no existing marker removed or narrowed
<!-- AC:END -->
