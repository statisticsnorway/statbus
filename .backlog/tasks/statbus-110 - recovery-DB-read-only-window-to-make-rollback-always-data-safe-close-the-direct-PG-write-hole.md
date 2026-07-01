---
id: STATBUS-110
title: >-
  recovery: DB read-only window to make rollback always data-safe (close the
  direct-PG write hole)
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-06-26 11:30'
updated_date: '2026-07-01 13:21'
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
documentation:
  - doc-018 - Read-only-upgrade-window-—-detailed-design-STATBUS-110.md
  - doc-019 - Recovery-decision-model-—-the-complete-picture.md
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PRIVILEGE-MODEL CORRECTION (verified vs running DB 2026-06-26): default_transaction_read_only AND transaction_read_only are BOTH context=user (USERSET); pg_parameter_acl is empty. => ANY role (not just admin) can `SET default_transaction_read_only=off` per-session and write. Demonstrated live: under RO a CREATE TABLE fails ('cannot execute CREATE TABLE in a read-only transaction'); after the same session flips the default off, it succeeds.

SO the read-only default is an ACCIDENT-GUARD, NOT an admin-gated lock: it REJECTS normal/accidental writes (error, not silent-write-then-lose) — which IS the data-safety bar (rollback stays safe vs the realistic threat: a careless direct-PG integrator) — but a DELIBERATE override by any user is possible (King-accepted: 'someone can work around it if they want to'). It is a speed bump, not a security boundary.

SIMPLIFICATION: the upgrade's own exemption is trivial — its migration session just does SET default_transaction_read_only=off for itself (USERSET, no special role/owner role needed). Remove the 'exempt owner role' option from the design; session-SET suffices.

IF a HARD boundary is ever required (regular users genuinely cannot write even deliberately; admin-only escape): use REVOKE write privileges from the app roles for the window, OR refuse their connections (Caddy Layer4 conditional route / pg_hba) — heavier, touches the RLS/grant model. DEFAULT plan stays accident-guard (cheap), per the King's stated intent; revisit only if the bar changes.

DECISION RATIFIED (King, 2026-06-26): build the read-only window as the ACCIDENT-GUARD (cheap path), NOT the hard admin-only lock.

PRINCIPLE (King's words): 'you cannot go wrong without intent; if you have intent you're allowed.' The system makes the dangerous thing impossible BY ACCIDENT and trivially possible DELIBERATELY. No accidental footguns; full deliberate control (the USERSET override IS the intended escape hatch, for the King to investigate when something stops).

NORTH STAR (why it matters): STATBUS upgrades run hands-off — an operator in Senegal/Uganda runs install and walks away. If recovery ever HOLDS for a human, that hands-off promise breaks → someone must physically intervene (fly out). The accident-guard keeps recovery AUTONOMOUS: accidental external writes blocked → rollback always data-safe → recovery self-decides (forward/rollback) → NO operator intervention. Autonomy is the goal; data-safety is the means.

NEXT: architect writes the detailed design (toggle on/off placement + the trivial session self-exemption) → engineer builds → arc-test (STATBUS-071). The hard admin-only mechanism is NOT needed; kept in notes only if the bar ever changes.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-01 13:09
---
BUILD STARTED (recovery-core GO, King 2026-07-01; sequence 110→109→046→111). Engineer deep-read the read-only-window design vs live code (design :NNNN cites from 06-26 are STALE — verified real: setMaintenance=exec.go:241 filesystem-flag; connect=service.go:2783, reconnect=2900 routes through connect; ON/OFF sites 4252/4262/4278/4869/5814). NO diff yet — 2 load-bearing DESIGN GAPS surfaced to the architect (foundation-not-fix) before wiring, because building as-written ships a KNOWN-BROKEN upgrade (phase-3 migrations all fail):

F2 (critical): phase-3 `./sb migrate up` runs as a SUBPROCESS via migrate.go's own psql, OUTSIDE Service.connect() → under ALTER DATABASE default_transaction_read_only=on every migration write FAILS. Empirically confirmed: superuser NOT exempt. Design asserts 'the upgrade's migrations succeed' = internal inconsistency; also breaks forward-recovery + boot-migrate-after-crash-freeze. Fix options A/B/C; engineer+foreman rec B (migrate.go psqlEnv adds PGOPTIONS=-c default_transaction_read_only=off — uniform, migrate always a writer). Architect ruling pending.

F1: rollback() OFF (:5814) is NOT unconditional — the git-restore-fail ABORT terminal (os.Exit :5733) leaves the box DOWN (no reconnect, no live conn) so read_only can't be cleared there. Rec (i): accept read_only persists (symmetric with maintenance-stays-ON = crash-freeze intent), `./sb install` recovery clears at its terminal — CONTINGENT on confirming the recovery path reliably clears read_only. Architect ruling pending.

F3 (confirm): ON-before-DB-stop bakes read_only=on into the phase-2 backup → every rollback-restore is read-only, must be actively cleared. Race-avoidance tradeoff (ON-early, no write-slip gap). Architect confirm pending.

On the 3 rulings → engineer implements the coherent unit one pass → foreman review+commit → push→CI image→VM arc-run (071, the only oracle). Commit HELD.
---

author: foreman
created: 2026-07-01 13:21
---
RULINGS RESOLVED (architect, code-verified) — engineer GREENLIT to build the coherent unit in one pass. F2=B (ADDITIVE to the connect() self-exempt, not a replacement: connect() self-exempt covers the Service's own pgx writes [completed UPDATE / flag / recovery ground-truth]; migrate.go psqlEnv PGOPTIONS=-c default_transaction_read_only=off covers the migrate SUBPROCESS — post-swap+boot+forward-recovery+dev, uniform, no-op when guard inactive). F1=(i) accept read_only persists on the git-restore-fail ABORT (crash-freeze intent, symmetric with maintenance-stays-ON); recovery clears at both successful terminals (forward →:4869, rollback →:5814) — CONFIRMED no leak; read_only TRACKS maintenance. F3=confirmed: keep ON before the DB stop (race-avoidance closes the reconnect-inherits-read-write hole at phase-3 restart); backup carrying read_only=on is fine since every rollback-restore reaches :5814→OFF. Live setMaintenance(false) sites = :4262/:4278/:4869/:5814; ON at ~:4245 conn-close; pre-swap-abort OFFs after reconnect. 046-composition note (for 046's build, not 110): an at-target parked box decides read_only+maintenance TOGETHER. Build → self-check → foreman diff-review + commit → push→CI image→VM arc-run 071 (the only oracle).
---
<!-- COMMENTS:END -->
