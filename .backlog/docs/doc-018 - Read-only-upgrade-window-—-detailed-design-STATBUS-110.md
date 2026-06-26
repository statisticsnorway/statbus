---
id: doc-018
title: Read-only upgrade window — detailed design (STATBUS-110)
type: specification
created_date: '2026-06-26 13:22'
updated_date: '2026-06-26 13:30'
tags:
  - upgrade
  - recovery
  - data-safety
  - statbus-110
---
# Read-only upgrade window — detailed design

Ticket: STATBUS-110. Ratified by the King 2026-06-26 as an **accident-guard** (not a security lock).

## The one reconciled picture (read this first)

An upgrade's timeline, with where the DB is, and where an external write actually lands relative to the snapshot a rollback would restore:

| phase | DB | an external write here… |
|---|---|---|
| 1. live → maintenance ON, app/rest stopped (`service.go:4201`,`:4207`) | up | …is committed before the stop → **captured in the snapshot → safe** |
| 2. stop DB (`:4223`) → backup = rsync the stopped volume (`:4249`) | **down** | …is impossible — DB is down. **The snapshot = this moment.** |
| 3. DB restarted, migrations → swap → post-swap migrate → health check | up | …lands **after the snapshot → LOST on a rollback-restore** |
| 4. maintenance OFF + `completed` (`:4828`) | up | …normal, upgrade done |

Rollback restores the snapshot (phase-2 state). So the **only** external writes a rollback can lose are the ones in **phase 3** — DB back up for migrations, but past the snapshot. Phase 1 is in the snapshot; phase 2 has no DB.

**That single fact reconciles the two things that looked contradictory:**
- *"The DB is down for the backup"* — true, so phase 2 carries **zero** write risk. The risk is only phase 3, after the DB restarts for migrations.
- *"Recovery can't roll back when it can't verify"* (the `GroundTruthUnknown` → hold-for-a-human path) — that conservatism exists for **one reason only**: to protect those phase-3 writes. If a crash lands in phase 3 and recovery can't confirm the state, a blind rollback might erase one.

**The read-only window guards exactly phase 3.** Block external writes there → a rollback can lose nothing → "can't verify" stops meaning "can't roll back" → recovery decides for itself, no human. One narrow risk window, one guard over it, and the conservatism it forced evaporates.

(Accident-guard, not a lock: a *deliberate* override can still write in phase 3 and is the user's own risk — per the ratified principle "can't go wrong without intent; with intent you're allowed.")

## Recommended approach
**Invariant:** every non-upgrade session is read-only across phase 3 (DB-available-after-snapshot → upgrade resolved).

1. **On** — `ALTER DATABASE <db> SET default_transaction_read_only = on`, issued while the DB is up and a connection is available, **before the stop (`:4223`)** so it is persisted in the catalog. When the DB is then stopped (which drops every connection) and restarted for migrations, *every* reconnecting session reads the new default. Setting it before the stop (not "at the restart") removes a race where a session reconnects before the ALTER lands and gets read-write. (The query conn closes at `:4196` — sequence the ALTER while a conn is available.)
2. **Self-exempt — per session, explicitly, on every (re)connect.** Issue `SET default_transaction_read_only = off` inside the upgrade's own `connect()` (`~:2746–2780`), so EVERY session it opens is read-write: pre-swap, the new sb's post-swap sessions, the completion-reconnect-on-stale-conn (`:4859+`), and recovery's sessions. Do NOT rely on a session having been opened before the ALTER — a mid-upgrade reconnect would otherwise re-inherit the read-only default and the upgrade's own `state='completed'` write would fail. (Engineer-flagged, 2026-06-26.)
3. **Crash-freeze** — `ALTER DATABASE … SET` persists in the catalog → a crash mid-phase-3 leaves the DB read-only on restart → the post-crash state is frozen (no external writes) → recovery opens onto a clean, snapshot-equivalent state.
4. **Off** — `ALTER DATABASE … = off` (idempotent) at **every** terminal: success completion (co-locate with `setMaintenance(false)`, `:4828`), the rollback path (`~:2198`), AND the recovery-driven terminals (`recoverFromFlag`→`recoveryRollback`; `recoverFromFlag`→`applyPostSwap` completion). Rule: wherever maintenance clears, clear read-only too — and ensure the recovery terminals clear both.

## Effect on recovery
With phase 3 write-free (against accidents), rollback can lose nothing → STATBUS-039 "never restore on a guess" retires → the *can't-verify → hold → human* branch collapses into safe-rollback / quiet-retry (STATBUS-109). Recovery self-decides → no operator travel.

## Critical files
- `cli/internal/upgrade/exec.go:242` `setMaintenance` — the toggle to mirror; add a sibling `setDatabaseReadOnly(bool)` (`ALTER DATABASE …`).
- `cli/internal/upgrade/service.go` — `:4201` maintenance ON · `:4223` stop db · `:4249` `backupDatabase` (snapshot) · the read-only ON site (before `:4223`) · the post-backup DB-restart-for-migrations point.
- `service.go:4828` + rollback path `~:2198` — `setMaintenance(false)` sites → co-locate read-only OFF.
- Recovery terminals: `recoverFromFlag` (`:766–977`), `recoveryRollback`, `applyPostSwap` (`:4481`) completion — read-only OFF must fire here too.
- `connect()` `~:2746–2780` — the single place the upgrade self-exempts (every upgrade/recovery session). `:4859+` — the completion reconnect that proves the per-session exemption is required.

## Verification (install-recovery arcs, STATBUS-071)
- **Accident blocked:** an external direct-PG session doing a normal write in phase 3 gets *"cannot execute … in a read-only transaction"*; the upgrade's own migrations + `completed` write succeed.
- **Intent allowed:** a session that does `SET default_transaction_read_only = off` then writes succeeds.
- **Crash-freeze:** kill mid-phase-3 → on restart the DB is still read-only → recovery rolls back cleanly, no external writes lost.
- **Every terminal clears it:** after success, after rollback, and after BOTH recovery terminals, `SHOW default_transaction_read_only` is off and external writes resume.

## Open questions
1. Exact OFF point on success — at/after the `completed` UPDATE (recommended), not the "hair before" maintenance lifts.
2. Do `recoveryRollback` / `applyPostSwap` completion already call `setMaintenance(false)`? — operator grounding in flight; co-locate read-only OFF, flag any terminal missing one.
3. Sequence the arc runs with the parked serialization/clean-restart decision (both arc-gated).
