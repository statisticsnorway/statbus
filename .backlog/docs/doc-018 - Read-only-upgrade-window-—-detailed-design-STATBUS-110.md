---
id: doc-018
title: Read-only upgrade window — detailed design (STATBUS-110)
type: specification
created_date: '2026-06-26 13:22'
tags:
  - upgrade
  - recovery
  - data-safety
  - statbus-110
---
# Read-only upgrade window — detailed design

Ticket: STATBUS-110. Ratified by the King 2026-06-26 as an **accident-guard** (not a security lock).

## Context
The upgrade's destructive+uncertain window must block **accidental** external writes so a rollback can never lose data — which makes recovery **autonomous** (no operator has to fly out). Principle (King): *"you cannot go wrong without intent; with intent you're allowed."* So: a DB-level read-only default that rejects a normal write with an error, but is deliberately overridable (USERSET escape hatch). Verified: `default_transaction_read_only` is `USERSET` (any session can self-exempt), so this is an accident-guard, not a boundary.

Where the data-loss window actually is (grounded):
- Maintenance ON (`service.go:4201`) gates **HTTP only** (app + `/rest`); the direct Layer4 Postgres path stays open.
- The DB is then **stopped** (`:4223 docker compose stop db`) and the snapshot is rsync'd from the stopped volume (`exec.go:478`, called at `service.go:4249`). Writes *before* the stop are captured in the snapshot — **not** lost on rollback.
- The danger is writes **after** the DB is restarted for migrations (post-`:4249`) through the rollback decision — those are past the snapshot and lost on a rollback-restore. That is the hole this closes.

## Recommended approach
**Invariant:** from the moment the DB is available after the snapshot until the upgrade definitively resolves (completed or rolled-back), every *non-upgrade* session is read-only.

1. **On** — at the post-backup DB restart for migrations (first point external sessions can reconnect after the snapshot), run `ALTER DATABASE <db> SET default_transaction_read_only = on`. Because the DB was just stopped (`:4223`) and restarted, **all prior connections are already dropped** — the catalog default cleanly applies to every reconnecting session. (The "existing connection" problem dissolves; no need to terminate backends.)
2. **Self-exempt** — the upgrade's migration session runs `SET default_transaction_read_only = off` for itself (USERSET, session-level; no special owner role). All migrate / post-swap DDL writes normally.
3. **Crash-freeze** — `ALTER DATABASE … SET` persists in the catalog, so a crash mid-window leaves the DB read-only on restart → the post-crash state is frozen (no external writes) → recovery always opens onto a clean, snapshot-equivalent state.
4. **Off** — `ALTER DATABASE <db> SET default_transaction_read_only = off` (idempotent) at **every** terminal: success completion (co-locate with `setMaintenance(false)` at `service.go:4828`), the rollback path (the `setMaintenance(false)` near `:2198`), **and the recovery-driven terminals** (`recoverFromFlag` → `applyPostSwap` completion; `recoverFromFlag` → `recoveryRollback`). Rule of thumb: wherever maintenance clears, clear read-only too — and make sure the recovery terminals clear both.

**Effect on the recovery model:** with the window provably write-free against accidents, rollback can't lose data → "never restore on a guess" (STATBUS-039) retires → the *can't-verify → hold → human* branch collapses into safe-rollback / quiet-retry (STATBUS-109). Recovery self-decides → no operator flight.

## Critical files
- `cli/internal/upgrade/exec.go:242` `setMaintenance` — the toggle to mirror; add a sibling `setDatabaseReadOnly(bool)` doing the `ALTER DATABASE`.
- `cli/internal/upgrade/service.go` — `:4201` maintenance ON · `:4223` stop db · `:4249` `backupDatabase` · the post-backup DB-restart-for-migrations point (**read-only ON here**).
- `service.go:4211 / 4227 / 4828` and the rollback path near `:2198` — `setMaintenance(false)` sites → co-locate read-only OFF.
- Recovery terminals: `recoverFromFlag` (`:766–977`), `recoveryRollback`, `applyPostSwap` (`:4481`) completion — ensure read-only OFF fires here too.
- The upgrade DB connection (`connect` `~:2746–2780`) — where the migration session self-exempts.

## Verification (install-recovery arcs, STATBUS-071)
- **Accident blocked:** an external direct-PG session doing a normal write mid-window gets *"cannot execute … in a read-only transaction"*; the upgrade's own migrations succeed.
- **Intent allowed:** a session that does `SET default_transaction_read_only = off` then writes succeeds (escape hatch intact).
- **Crash-freeze:** kill mid-window → on restart the DB is still read-only → recovery rolls back cleanly, no external writes lost.
- **Every terminal clears it:** after success, after rollback, and after BOTH recovery terminals, `SHOW default_transaction_read_only` is off and external writes resume.

## Open questions
1. Exact OFF point on success — at the `completed` UPDATE, or the same "hair before" as maintenance (the benign gap)? Recommend at/after `completed` (no reason to reopen writes early).
2. Do `recoveryRollback` / `applyPostSwap` completion already call `setMaintenance(false)`? If not, this design adds the first such call there — confirm and co-locate. (Delegate-able grounding.)
3. Sequence the arc runs with the parked serialization/clean-restart decision (both arc-gated).
