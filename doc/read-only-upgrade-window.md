# Read-only upgrade window — detailed design

*Canonical home (lifted into `doc/` from the backlog 2026-06-29). The detailed design of the read-only window — the **accident-guard that makes a rollback data-safe**, which is what lets the recovery model roll back autonomously. See `doc/upgrade-recovery-model.md` for the recovery model this enables, and `doc/upgrade-vocabulary.md` for the names. Ticket: STATBUS-110.*

Ratified by the King 2026-06-26 as an **accident-guard** (not a security lock).

## The one reconciled picture (read this first)

An upgrade's timeline, with where the DB is, and where an external write actually lands relative to the snapshot a rollback would restore:

| phase | DB | an external write here… |
|---|---|---|
| 1. live → read-only ON (`service.go:4799`) → maintenance ON, app/rest stopped (`:4822`) | up | …is committed before the stop → **captured in the snapshot → safe** |
| 2. stop DB → backup = rsync the stopped volume (`backupDatabase`, `:4878`) | **down** | …is impossible — DB is down. **The snapshot = this moment.** |
| 3. DB restarted, migrations → swap → post-swap migrate → health check | up | …non-exempt writes are refused by the window; exempt writes are ours and rollback restores past them by design |
| 4. maintenance OFF (`:5596`) + read-only OFF (`:5668`) + `completed` | up | …the box is serving on purpose; complete it, never start a rollback |

*(Line cites re-verified 2026-07-12 against the shipped STATBUS-145/154/159 geometry; anchor on the function names if they drift again.)*

Rollback restores the snapshot (phase-2 state). During phase 3, the read-only window defines every write disposition: non-exempt writes are refused; exempt-writer changes are upgrade machinery state that the restore intentionally rewinds; and a deliberate non-exempt override is the writer's decision to forfeit that write. Phase 1 is captured in the snapshot; phase 2 has no DB.

**That single contract reconciles the timeline:**
- *"The DB is down for the backup"* — true, so phase 2 admits no writes.
- *"The DB is up again after the snapshot"* — also true, but the window already defines those writes as refused or intentionally disregarded by a restore. They are not a rollback hedge.

**The read-only window guards exactly phase 3.** Window ON → rollback is lossless, always. This removes write preservation from the direction decision: recovery may retry, roll back, complete, or park for its named state-machine reason, but never because a during-window write needs protecting.

(Accident-guard, not a lock: a *deliberate* non-exempt override can still write in phase 3, but that act deliberately forfeits the write. A later rollback disregards it by design — per the ratified principle "can't go wrong without intent; with intent you're allowed.")

## Recommended approach
**Invariant:** every non-upgrade session is read-only across phase 3 (DB-available-after-snapshot → upgrade resolved), with ONE role exception — `authenticator` (PostgREST), exempted at the role level (item 3 below) because its listener would otherwise crash-loop and 503 the health check; external `/rest` writes stay frozen by the maintenance 503 regardless (doc-023).

1. **On** — `ALTER DATABASE <db> SET default_transaction_read_only = on` (`setDatabaseReadOnly`, `exec.go:341-380`; ON site `service.go:4799`), issued while the DB is up and a connection is available, **before maintenance ON (`:4822`) and the stop/backup (`:4878`)** so it is persisted in the catalog. When the DB is then stopped (which drops every connection) and restarted for migrations, *every* reconnecting session reads the new default. Setting it before the stop (not "at the restart") removes a race where a session reconnects before the ALTER lands and gets read-write.
2. **Self-exempt — per session, explicitly, on every (re)connect.** `SET default_transaction_read_only = off` on the daemon's own sessions: `connect()` exempts `queryConn` + `listenConn` (`service.go:3254`/`:3259`), and — added by STATBUS-154's teardown-immune terminal writes — `terminalUpdate` exempts its ALWAYS-FRESH per-write session the same way (`:6734`; wave-6 proved a fresh mid-window session otherwise inherits read-only and the park write fails with SQLSTATE 25006). Do NOT rely on a session having been opened before the ALTER — a mid-upgrade reconnect re-inherits the read-only default.
3. **Exempt the `authenticator` role (PostgREST) — role-GUC, durable in the schema (STATBUS-110 regression fix, doc-023).** `ALTER ROLE authenticator SET default_transaction_read_only = off`. **Durable homes (the original migration `20260703104910` was DELETED — never in a released tag):** `migrations/post_restore.sql:36` (re-armed on every `migrate up`) + `postgres/init-db.sh:154` (armed at cluster birth). PostgREST's `pgrst`-channel LISTENER opens with `target_session_attrs=read-write`, so under the database read-only default libpq rejects it (`session is read-only`) → `/ready` 503 → the post-upgrade health check never passes → the upgrade wedges/rolls back. Role-GUC **outranks** database-GUC, so the authenticator session reports *writable* and the listener connects — while the database default still freezes every other role. The **exempt-writer roster (five)**: `queryConn`/`listenConn` (connect), the `migrate` subprocess (`psqlEnv` PGOPTIONS), the post-swap sessions, `terminalUpdate`'s fresh terminal-write sessions (STATBUS-154), and the `authenticator` role — the last being the only NON-upgrade exemption (PostgREST liveness) and the only schema-durable one. It opens **no external write path**: PostgREST's external `/rest` writes are maintenance-503-gated (Caddy `@maintenance`) throughout the window — 110's unique contribution was the direct-PG (Layer4) path, which uses OTHER roles, not `authenticator`. The worker, app role, and every direct-PG integrator role stay frozen (correct); the worker sets no `target_session_attrs` so it does not crash-loop, only its writes fail (the intended freeze).
4. **Crash-freeze** — `ALTER DATABASE … SET` persists in the catalog → a crash mid-phase-3 leaves the DB read-only on restart → the post-crash state is frozen (no external writes) → recovery opens onto a clean, snapshot-equivalent state. The authenticator role-GUC likewise persists, so post-crash PostgREST comes up **healthy** while maintenance still gates external `/rest` and read-only still gates the worker/app/direct-PG roles. **Empirical oracle:** the STATBUS-110 AC#2 rider on `postswap-mid-tx-kill-arc` probes exactly this — post-kill/pre-recovery a fresh non-exempt session must see `SHOW = on` AND a blocked write; after the recovery terminal, `off` AND a write succeeding.
5. **Off — every terminal clears it, except the one deliberate hold** (verified 2026-07-12; the old "co-located at the four `setMaintenance(false)` sites" framing predates the STATBUS-154 terminal consolidation):
   - `service.go:4832` and `:4852` — `executeUpgrade` pre-swap abort paths (co-located with their maintenance OFF).
   - `:5668` — completion, placed **deliberately AFTER the `completed` UPDATE landed** (not at the earlier maintenance-OFF `:5596`): `queryConn` is only guaranteed live once the completed write's reconnect loop has succeeded, so clearing earlier could silently miss on a stale conn and leak read-only. Also the recovery-forward terminal (`recoverFromFlag`→`resumePostSwap`→`applyPostSwap`).
   - `:6899` — inside `rollback()`, the choke point for every rollback path — and load-bearing beyond co-location: the **restored snapshot CARRIES `default_transaction_read_only = on` in its catalog** (it was ALTERed before the pre-stop backup), so without this explicit re-clear the rolled-back, serving box would reject external writes.
   - **The deliberate exception:** the git-restore-fail ABORT terminal exits with read-only ON alongside maintenance ON — the box is degraded/down and the operator's `./sb install` recovery clears both at its successful terminal. A frozen degraded box is the intended state, not a missed OFF.

## Effect on recovery — the formal supersession (STATBUS-110 AC#3, 2026-07-12)
**The read-only-window invariant SUPERSEDES STATBUS-039's "never restore on a guess."** The old doctrine was a categorical prohibition born of one risk: a restore could erase an external write that landed after the snapshot. The window removes the risk instead of prohibiting the action — with phase 3 write-free (against accidents), **a rollback is universally data-safe by construction**, so the *can't-verify → hold → human* branch collapses into safe-rollback / quiet-retry (STATBUS-109), and recovery self-decides with no operator travel. The successor doctrine, as the recovery decision model states it: *classify-then-act, with rollback as the universal safe fallback; the only human stops are "unknown" (unreadable own-state / unrecognized error) and "restore-broke" (the restore mechanism itself failed) — neither is a data-safety hold.* `doc/upgrade-recovery-model.md` is the canonical decision tree; this document is the invariant that makes its autonomy sound.

## Parked-window repair (STATBUS-380)

A parked upgrade can require a deliberate data or schema correction while its
read-only accident-guard remains active. `./sb install` is not a repair interval:
it un-parks and immediately starts one fresh recovery attempt, so it cannot
reliably leave the operator a safe point to make that correction.

Use the single sanctioned verb instead:

```bash
./sb upgrade repair --file tmp/repair.sql --reason "why this is needed" --operator "Name"
```

The command requires an `in_progress` row with `recovery_parked_at`, self-exempts
only its own psql session, locks the parked row, and runs the supplied SQL and an
`upgrade_state_log` entry in one transaction. The entry records the operator,
reason, connection, and that this was a parked-window repair. It rejects empty
files and top-level `BEGIN`, `COMMIT`, or `ROLLBACK`, because the verb owns the
one atomic transaction. A later snapshot restore intentionally forfeits both the
repair and its audit record, just as it forfeits every deliberate phase-3 write.

Do not use raw admin psql for this flow. The exemption remains a PostgreSQL
accident-guard escape hatch for product maintenance, not an operator API.

## Cost and acceptability
During an upgrade's destructive window, external writes are blocked while reads keep working. This costs little in practice: browser and REST traffic already stop in this window under maintenance mode, so the only new restriction falls on a direct database connection, which few real users make. Upgrades are infrequent and this window lasts minutes, not hours, so a short write pause is a small price for a statistical registry. The block is a guard against accidents, not a lock: any session can deliberately turn it off for itself, but doing so deliberately forfeits that write if rollback restores the snapshot. The ratified rule is that you cannot go wrong without meaning to, and if you mean to, you are allowed. In exchange, the payoff is categorical: window ON means rollback is lossless by definition, which lets an unreachable box recover by itself instead of waiting for a human to travel there.

## Critical files (re-verified 2026-07-12)
- `cli/internal/upgrade/exec.go:341-380` — `setDatabaseReadOnly(bool)` (`ALTER DATABASE …`), the sibling of `setMaintenance`.
- `cli/internal/upgrade/service.go:4799` — ON (before maintenance ON `:4822` and the snapshot `:4878`).
- OFF sites: `:4832`/`:4852` (pre-swap aborts) · `:5668` (completion, AFTER the completed UPDATE — see item 5) · `:6899` (`rollback()` — also re-clears the snapshot-carried read-only). ABORT deliberately holds it ON.
- Self-exemptions: `connect()` `:3254`/`:3259` (queryConn + listenConn) · `terminalUpdate` `:6734` (STATBUS-154, every fresh terminal-write session) · `migrate` subprocess PGOPTIONS · authenticator role-GUC (`migrations/post_restore.sql:36`, `postgres/init-db.sh:154`).

## Verification (install-recovery arcs, STATBUS-071)
- **Accident blocked:** an external direct-PG session doing a normal write in phase 3 gets *"cannot execute … in a read-only transaction"*; the upgrade's own migrations + `completed` write succeed.
- **Intent allowed:** a session that does `SET default_transaction_read_only = off` then writes succeeds.
- **Crash-freeze (STATBUS-110 AC#2 — rider shipped on `postswap-mid-tx-kill-arc`, 2026-07-12):** kill mid-phase-3 → post-kill/pre-recovery a fresh non-exempt session sees `SHOW = on` AND a write blocked (25006); after the recovery terminal, `off` AND a self-cleaning write succeeds. The co-assert (SHOW + blocked write) is deliberate: a silent role exemption cannot fake a green.
- **Every terminal clears it** except the deliberate ABORT hold (item 5): after success, after rollback, and after the recovery-forward terminal, `SHOW default_transaction_read_only` is off and external writes resume.
