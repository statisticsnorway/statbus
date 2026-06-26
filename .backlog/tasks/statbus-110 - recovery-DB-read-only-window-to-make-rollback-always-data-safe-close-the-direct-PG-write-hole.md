---
id: STATBUS-110
title: >-
  recovery: DB read-only window to make rollback always data-safe (close the
  direct-PG write hole)
status: To Do
assignee: []
created_date: '2026-06-26 11:30'
updated_date: '2026-06-26 12:10'
labels:
  - upgrade
  - recovery
  - data-safety
dependencies: []
references:
  - doc/upgrade-vocabulary.md
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
  - STATBUS-107
  - STATBUS-039
  - STATBUS-071
  - STATBUS-109
priority: medium
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why
Surfaced reopening the "never restore on a guess" invariant (STATBUS-107 walkthrough, King 2026-06-26). During an upgrade's destructive+uncertain window the DIRECT Postgres path (Caddy Layer4 TCP) is UNGATED — maintenance mode is HTTP-only. A client with DB creds (a direct-PG integrator) can write during the window, and those writes are LOST on a rollback-restore. That data-loss risk is WHY recovery must never restore-on-a-guess (STATBUS-039) and instead holds for a human under uncertainty.

## Grounded facts (operator + team-lead verified; tmp/operator-upgrade-write-gating.md)
- Topology: external clients reach PG via Caddy Layer4 on PUBLIC ports; the upgrade service connects via Caddy Layer4 on the LOOPBACK bind (CADDY_DB_BIND_ADDRESS/PORT, sslmode=disable), service.go connect ~2746-2780. SEPARABLE routes — external could be blocked while keeping the upgrade's own access.
- Maintenance: set exec.go:257 ($HOME/statbus-maintenance/active); ON at service.go:4201 before destructive steps; cleared 4211/4227 (rollback) / 4828 (success) / 5684. @maintenance Caddy matcher 503s app + /rest (except auth) — HTTP/HTTPS ONLY; the Layer4 TCP DB proxy is NOT tied to it.
- DANGEROUS window = snapshot-taken → rollback-decision (migrations running, maintenance ON): browser + /rest gated, but direct Layer4 DB UNGATED → the data-safety hole.
- The 4828→4853 post-completion gap (maintenance lifts a hair before the `completed` UPDATE) is BENIGN — after the health check, no rollback pending.
- NO existing block-all-external-writes capability (no Layer4 conditional route, no pg_hba template, no DB read-only mode).

## Proposed lever
DB-level read-only toggle: ALTER DATABASE ... SET default_transaction_read_only = on before the destructive window, off after definitive completion. ONE chokepoint catching EVERY path at once (Layer4 + REST + auth) — no Caddy/Layer4 conditional-routing gymnastics. Persists across a crash (catalog setting) → the post-crash state is FROZEN (no external writes) until recovery decides → recovery always has a clean state. Caveat: the upgrade's own migration connection must be EXEMPTED (session SET transaction_read_only=off, or an exempt owner role); handle in-flight connections + superuser semantics.

## Payoff
- Closes the direct-PG write hole.
- Removes the data-loss RISK from rollback → relaxes STATBUS-039: under a guaranteed write-free window, rollback-under-uncertainty is data-safe, so recovery DIRECTION (forward-retry vs rollback) becomes an availability/disruption choice, NOT a data-safety one. Potentially collapses the "can't-verify → hold → human" branch.

## Cost
External WRITES blocked (reads OK) for the upgrade window. The common write paths (browser + REST uploads) are ALREADY gated by maintenance — this only adds the direct-PG path, so the incremental write-block is narrow. For an infrequently-upgraded registry, likely acceptable.

## Must be arc-tested
Behavior change to upgrade + recovery — prove via install-recovery arcs (STATBUS-071), incl. an arc that writes directly to PG mid-window and verifies the read-only block + clean rollback. Coordinate with STATBUS-109 (in-process backoff) and the parked byte/clean-restart decision.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 During the destructive+uncertain window, ALL external writes (browser, REST, AND direct Layer4 PG) are blocked while the upgrade's own migration session writes successfully (exempt) — proven by an install-recovery arc
- [ ] #2 The read-only state persists across a mid-window crash so the post-crash state is frozen until recovery decides
- [ ] #3 With the window guaranteed write-free, rollback-under-uncertainty is shown data-safe (no external writes to lose); STATBUS-039 'never restore on a guess' is re-evaluated and the recovery decision tree updated accordingly
- [ ] #4 Cost/acceptability of the read-only write-window documented (reads stay available; upgrades are infrequent)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## The recovery decision tree this re-grounds (current behavior — STATBUS-107 walkthrough, 11 paths)
- ACQUIRE-AND-RETRY (transient): `recovery-new-sb-retrying-db` (db unreachable → retry) · `recovery-new-sb-fetching-commit` (target commit not in clone → git fetch/deepen)
- KNOWN RECOVERY: `recovery-old-sb-never-swapped` (restart old) · `recovery-new-sb-completed-migrations` (finish bookkeeping) · `recovery-new-sb-pending-migrations` (one-shot rollback)
- STOP FOR A HUMAN: `recovery-stuck-needs-human` (acquire exhausted) · `recovery-unexpected-state` (unrecognized phase)
- HOUSEKEEPING: `recovery-nothing-pending` · `recovery-discard-corrupt-flag` · `recovery-clear-install-flag`
- EDGE (defensive): `recovery-binary-mismatch`

## Why the current model is conservative (and likely an under-ratified agent assumption)
"never restore on a guess" (STATBUS-039) + the whole "can't-verify → hold → human" branch exist ONLY because the direct-PG path is ungated during the destructive window (this ticket's hole) — so a rollback might erase a direct-PG integrator's writes. Close that hole and rollback loses nothing; the conservatism becomes unnecessary.

## Target model once the read-only window lands (110 + 109 compose)
With a guaranteed write-free window, rollback is ALWAYS data-safe. Recovery simplifies to:
- Transient (db down / commit missing) → QUIET in-process retry (STATBUS-109), no exit-noise.
- Forward logically possible → finish forward.
- Can't go forward (confirmed behind, or can't-verify and it won't resolve) → ROLL BACK safely → operator re-schedules.
- Truly unnameable (unrecognized phase) → stop for a human.
Net: the "can't-verify → hold → human" branch DISSOLVES into safe-rollback or quiet-retry; `recovery-stuck-needs-human` survives only for the genuinely unnameable.

## Decision needed (King ratifies — do NOT build without it)
Adopt the read-only window as the recovery-correctness FOUNDATION, vs keep the conservative never-restore model and merely reduce its noise via STATBUS-109? Architect recommends ADOPT: it closes the real hole and makes the system BOTH safer AND simpler, at the cost of a write-paused (reads-OK) window per upgrade — modest for an infrequently-upgraded registry.

## Path to conclusion
1. King ratifies the direction.
2. Architect writes the detailed design: toggle placement in executeUpgrade (on before destructive steps, off at confirmed completion), the upgrade-session exemption mechanism, in-flight-connection + superuser handling, and the simplified recovery decision tree.
3. Engineer builds; PROVE via install-recovery arcs (STATBUS-071): a direct-PG-write-mid-window arc + the simplified-recovery arcs.
4. Lock the registry (doc/upgrade-vocabulary.md) recovery names to the simplified set.
5. Formally supersede STATBUS-039 "never restore on a guess" with the read-only-window invariant; note it in doc/upgrade-timeline.md.
6. Land STATBUS-109 (quiet transient retry) as the composable partner.
<!-- SECTION:PLAN:END -->
