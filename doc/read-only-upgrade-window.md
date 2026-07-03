# Read-only upgrade window — detailed design

*Canonical home (lifted into `doc/` from the backlog 2026-06-29). The detailed design of the read-only window — the **accident-guard that makes a rollback data-safe**, which is what lets the recovery model roll back autonomously. See `doc/upgrade-recovery-model.md` for the recovery model this enables, and `doc/upgrade-vocabulary.md` for the names. Ticket: STATBUS-110.*

Ratified by the King 2026-06-26 as an **accident-guard** (not a security lock).

## The one reconciled picture (read this first)

An upgrade's timeline, with where the DB is, and where an external write actually lands relative to the snapshot a rollback would restore:

| phase | DB | an external write here… |
|---|---|---|
| 1. live → maintenance ON, app/rest stopped (`service.go:4201`,`:4207`) | up | …is committed before the stop → **captured in the snapshot → safe** |
| 2. stop DB (`:4223`) → backup = rsync the stopped volume (`:4249`) | **down** | …is impossible — DB is down. **The snapshot = this moment.** |
| 3. DB restarted, migrations → swap → post-swap migrate → health check | up | …lands **after the snapshot → LOST on a rollback-restore** |
| 4. maintenance OFF + `completed` (`:4828`/`:4853`) | up | …normal, upgrade done |

Rollback restores the snapshot (phase-2 state). So the **only** external writes a rollback can lose are the ones in **phase 3** — DB back up for migrations, but past the snapshot. Phase 1 is in the snapshot; phase 2 has no DB.

**That single fact reconciles the two things that looked contradictory:**
- *"The DB is down for the backup"* — true, so phase 2 carries **zero** write risk. The risk is only phase 3, after the DB restarts for migrations.
- *"Recovery can't roll back when it can't verify"* (the `GroundTruthUnknown` → hold-for-a-human path) — that conservatism exists for **one reason only**: to protect those phase-3 writes. If a crash lands in phase 3 and recovery can't confirm the state, a blind rollback might erase one.

**The read-only window guards exactly phase 3.** Block external writes there → a rollback can lose nothing → "can't verify" stops meaning "can't roll back" → recovery decides for itself, no human. One narrow risk window, one guard over it, and the conservatism it forced evaporates.

(Accident-guard, not a lock: a *deliberate* override can still write in phase 3 and is the user's own risk — per the ratified principle "can't go wrong without intent; with intent you're allowed.")

## Recommended approach
**Invariant:** every non-upgrade session is read-only across phase 3 (DB-available-after-snapshot → upgrade resolved), with ONE role exception — `authenticator` (PostgREST), exempted at the role level (item 3 below) because its listener would otherwise crash-loop and 503 the health check; external `/rest` writes stay frozen by the maintenance 503 regardless (doc-023).

1. **On** — `ALTER DATABASE <db> SET default_transaction_read_only = on`, issued while the DB is up and a connection is available, **before the stop (`:4223`)** so it is persisted in the catalog. When the DB is then stopped (which drops every connection) and restarted for migrations, *every* reconnecting session reads the new default. Setting it before the stop (not "at the restart") removes a race where a session reconnects before the ALTER lands and gets read-write. (The query conn closes at `:4196` — sequence the ALTER while a conn is available.)
2. **Self-exempt — per session, explicitly, on every (re)connect.** Issue `SET default_transaction_read_only = off` inside the upgrade's own `connect()` (`~:2746–2780`), so EVERY session it opens is read-write: pre-swap, the new sb's post-swap sessions, the completion-reconnect-on-stale-conn (`:4859+`), and recovery's sessions. Do NOT rely on a session having been opened before the ALTER — a mid-upgrade reconnect would otherwise re-inherit the read-only default and the upgrade's own `state='completed'` write would fail. (Engineer-flagged, 2026-06-26.)
3. **Exempt the `authenticator` role (PostgREST) — role-GUC, durable in a migration (STATBUS-110 regression fix, doc-023).** `ALTER ROLE authenticator SET default_transaction_read_only = off` (migration `20260703104910`). PostgREST's `pgrst`-channel LISTENER opens with `target_session_attrs=read-write`, so under the database read-only default libpq rejects it (`session is read-only`) → `/ready` 503 → the post-upgrade health check never passes → the upgrade wedges/rolls back. Role-GUC **outranks** database-GUC, so the authenticator session reports *writable* and the listener connects — while the database default still freezes every other role. This is the **fourth exempt writer** (alongside `queryConn`, the `migrate` subprocess, and the post-swap sessions), but the only one exempted for a NON-upgrade reason (PostgREST liveness), and it is expressed **durably in the schema** rather than per-session. It opens **no external write path**: PostgREST's external `/rest` writes are maintenance-503-gated (Caddy `@maintenance`) throughout the window — 110's unique contribution was the direct-PG (Layer4) path, which uses OTHER roles, not `authenticator`. The worker, app role, and every direct-PG integrator role stay frozen (correct); the worker sets no `target_session_attrs` so it does not crash-loop, only its writes fail (the intended freeze).
4. **Crash-freeze** — `ALTER DATABASE … SET` persists in the catalog → a crash mid-phase-3 leaves the DB read-only on restart → the post-crash state is frozen (no external writes) → recovery opens onto a clean, snapshot-equivalent state. The authenticator role-GUC likewise persists, so post-crash PostgREST comes up **healthy** (listener connects, `/ready` green) while maintenance still gates external `/rest` and read-only still gates the worker/app/direct-PG roles — strictly better than the pre-fix crash-loop, external freeze unchanged.
5. **Off** — `ALTER DATABASE … = off` (idempotent) co-located at the **four** `setMaintenance(false)` sites (verified 2026-06-26):
   - `service.go:4211` and `:4227` — `executeUpgrade` pre-swap abort paths.
   - `:4828` — `applyPostSwap` success/completion (also the **recovery-forward** terminal, via `recoverFromFlag`→`resumePostSwap`→`applyPostSwap`).
   - `:5684` — inside `rollback()`: the **single choke point for EVERY rollback path** — direct `executeUpgrade` calls, `recoveryRollback`→`rollback()`, and the positively-behind recovery rollback all funnel here.
   Idempotent `off` is harmless where read-only wasn't set, so these four spots cover all terminals. **Build-time check:** confirm `:5684` is reached **unconditionally** within `rollback()` (not after an early return) so a degraded rollback can't skip the OFF.

## Effect on recovery
With phase 3 write-free (against accidents), rollback can lose nothing → STATBUS-039 "never restore on a guess" retires → the *can't-verify → hold → human* branch collapses into safe-rollback / quiet-retry (STATBUS-109). Recovery self-decides → no operator travel.

## Critical files
- `cli/internal/upgrade/exec.go:242` `setMaintenance` — the toggle to mirror; add a sibling `setDatabaseReadOnly(bool)` (`ALTER DATABASE …`).
- `cli/internal/upgrade/service.go` — `:4201` maintenance ON · `:4223` stop db · `:4249` `backupDatabase` (snapshot) · the read-only ON site (before `:4223`).
- OFF co-location (the four `setMaintenance(false)` sites): `:4211`, `:4227`, `:4828` (success + recovery-forward), `:5684` (`rollback()` — single choke for all rollback + recovery-rollback).
- `connect()` `~:2746–2780` — the single place the upgrade self-exempts (every upgrade/recovery session). `:4859+` — the completion reconnect that proves the per-session exemption is required.

## Verification (install-recovery arcs, STATBUS-071)
- **Accident blocked:** an external direct-PG session doing a normal write in phase 3 gets *"cannot execute … in a read-only transaction"*; the upgrade's own migrations + `completed` write succeed.
- **Intent allowed:** a session that does `SET default_transaction_read_only = off` then writes succeeds.
- **Crash-freeze:** kill mid-phase-3 → on restart the DB is still read-only → recovery rolls back cleanly, no external writes lost.
- **Every terminal clears it:** after success, after rollback, and after BOTH recovery terminals, `SHOW default_transaction_read_only` is off and external writes resume.

## Open questions / build-time checks
1. RESOLVED — OFF co-locates with maintenance, including `:4828` (a hair before the `completed` UPDATE at `:4853`): benign, because the health check has already passed there and no rollback is pending; reopening writes is fine.
2. RESOLVED (verified 2026-06-26) — the four co-location sites above. `recoveryRollback` and `applyPostSwap` completion both already clear maintenance (`recoveryRollback`→`rollback()`→`:5684`; completion→`:4828`); no terminal is missing one.
3. BUILD-TIME — confirm `:5684` is unconditional within `rollback()` (the one remaining check on OFF coverage).
4. Sequence the arc runs with the parked serialization/clean-restart decision (both arc-gated).
