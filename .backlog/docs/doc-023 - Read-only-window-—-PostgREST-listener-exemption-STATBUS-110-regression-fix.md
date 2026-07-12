---
id: doc-023
title: Read-only window — PostgREST listener exemption (STATBUS-110 regression fix)
type: specification
created_date: '2026-07-02 18:46'
updated_date: '2026-07-12 03:29'
tags:
  - upgrade
  - recovery
  - data-safety
  - statbus-110
  - postgrest
  - regression-fix
---
# Read-only window — PostgREST listener exemption (STATBUS-110 regression fix)

*Architect, 2026-07-02. Amends `doc/read-only-upgrade-window.md` (STATBUS-110). For King nod before build — this refines the ratified 110 semantics (adds one exempt role). Mechanism grounded first-hand in code + the repro logs (tmp/mechanic-rest-readonly-{baseline,repro}.log) + both VM arcs (run 28609876020).*

> **DELIVERY STATUS (architect, 2026-07-12 — the shipped vehicle differs from §Delivery below):** the exemption shipped and holds, but NOT as the recommended migration — migration `20260703104910` was DELETED (never in a released tag). The durable homes are **`migrations/post_restore.sql:36`** (re-armed on every `migrate up`) and **`postgres/init-db.sh:154`** (armed at cluster birth). The design's rationale (role-GUC outranks database-GUC; declarative, durable, version-independent) is unchanged and is what those two homes express. Current canonical description: `doc/read-only-upgrade-window.md` (exempt-writer roster of five — the STATBUS-154 `terminalUpdate` sessions joined after this doc was written). The §Delivery and §change-set text below is the design history, kept as written.

## The regression
STATBUS-110's read-only window (`ALTER DATABASE … SET default_transaction_read_only = on`, engaged before the destructive phase) makes **every upgrade fail its health check**. Under read-only, PostgREST loops forever:

```
Failed listening for notifications on the "pgrst" channel. Just "connection to server at
"db" (172.21.0.6), port 5432 failed: session is read-only" → retry in 2,4,8,16,32,32… s
```

→ `/ready` returns 503 → the post-upgrade health check (step 12, `waitForRestReady`/`healthCheck`) never passes → the upgrade rolls back or wedges. Confirmed on both VM arcs (run 28609876020).

## Grounded mechanism (first-hand)
- **`PGRST_DB_URI = postgres://authenticator:…@db:5432/statbus_<slot>`** (docker-compose.rest.yml:12) — a plain URI, **no `target_session_attrs`**. Grep confirms `target_session_attrs` appears **nowhere** in our repo.
- **PostgREST's connection POOL works** under read-only: the baseline vs repro logs show the schema cache still loads in 13ms (reads are allowed). So the failure is **not** all REST connections.
- **PostgREST's notification LISTENER fails at connect.** The error `connection … failed: session is read-only` is emitted by **libpq only** for its `target_session_attrs=read-write` (primary) check: libpq runs `SHOW transaction_read_only`, and on `on` it rejects the connection. Since our URI doesn't set it, **PostgREST v12 opens its `pgrst`-channel listener with `target_session_attrs=read-write` internally** (it wants the LISTEN channel on the writable primary). `default_transaction_read_only = on` makes the primary report read-only → the listener is rejected → infinite retry (cap 32s) → and **v12.2.8's `/ready` requires that listener healthy** → 503.
- **The fix does not depend on PostgREST's exact internal reason** — it only needs `authenticator`'s session to report *writable*. A role-level exemption delivers that regardless of PostgREST version (composes with the STATBUS-054 v12→v14 bump, where the listener strategy may change).
- **The upgrade's own writers are already exempt** (STATBUS-110): the service's `queryConn` self-exempts in `connect()`; `migrate up` runs with `PGOPTIONS=-c default_transaction_read_only=off`. Only PostgREST was missed.

**Scope: it is ONLY PostgREST's listener**, because only PostgREST uses `target_session_attrs=read-write`. Our own app/worker LISTEN (app/src/lib/db-listener.ts, role `statbus_notify_<slot>`) sets no such attr → it connects fine under read-only and only its *writes* fail (the intended freeze). So there is no crash-loop anywhere except PostgREST, and no other role needs exemption.

## Recommended lever — exempt the `authenticator` role (role-GUC outranks database-GUC)
Add a migration:

```sql
-- up
ALTER ROLE authenticator SET default_transaction_read_only = off;
-- down
ALTER ROLE authenticator RESET default_transaction_read_only;
```

PostgreSQL precedence is per-role > per-database, so a session logging in as `authenticator` starts with `transaction_read_only = off` even while the database default is `on`. PostgREST's listener then passes libpq's read-write check and connects; `/ready` goes green; the health check passes.

**Where this breaks the circular deadlock (named explicitly).** The deadlock is: completion requires `/ready`=200 → `/ready` requires the listener → the listener requires a read-write session → a read-write session (via the database-GUC) returns only at completion. The fix cuts the **third edge**: the authenticator role-GUC makes the listener's *session* writable **independently of the database-GUC and of completion**. The listener now connects while the database is still `read-only` (mid-window, pre-completion) → `/ready` goes green → completion proceeds → the window lifts normally. The cycle is broken because "the listener requires read-write" is satisfied by the *role*, not by the database default that only clears at completion. (Confirmed by the mechanic: the listener connects as the **same db-uri role** — authenticator — so a role-level exemption covers exactly that connection.)

**Why this preserves the accident-guard intent:**
- PostgREST's *external* data-writes (POST/PATCH) are **already gated by the maintenance 503** (Caddy `@maintenance` matcher 503s `/rest` except auth), throughout the window — the read-only default was never the gate for the REST path. 110's *unique* contribution was the **direct-PG (Layer4)** path, which uses **other roles**, not `authenticator`.
- So exempting `authenticator` opens **no new external write path**: REST stays maintenance-gated, direct-PG integrators stay read-only-gated.

### Role-by-role table (the King's bar)
| role | who uses it | exempt? | why | can it write during the window? |
|---|---|---|---|---|
| `authenticator` | PostgREST (pool **and** listener) | **YES** (this fix) | its listener uses `target_session_attrs=read-write`; libpq rejects a read-only session → `/ready` 503 → health-check fails | at the DB level yes, but external `/rest` is **maintenance-503-gated**, so no external write reaches it; only internal reads (health/schema-cache) run |
| `anon` / `authenticated` | PostgREST per-request (`SET ROLE` from authenticator) | inherit (session already off) | `SET ROLE` does not re-evaluate role GUCs | DB-level yes, but **maintenance-503-gated** externally |
| upgrade `queryConn` (pgx) | the upgrade service | already (110, `connect()` self-exempt) | writes `completed`/flag/recovery state | yes — intended |
| migrate subprocess | `./sb migrate up` | already (110, `PGOPTIONS`) | the upgrade's DDL | yes — intended |
| `statbus_<slot>` (app) / `statbus_notify_<slot>` | the WORKER + the Next.js app | **NO — stays guarded** | these are the post-snapshot writers the window must freeze so a rollback loses nothing | **NO** — writes blocked by read-only (correct); LISTEN still connects (no read-write attr → no crash-loop) |
| direct-PG integrator roles | external Layer4 clients | **NO — stays guarded** | the accident-guard's entire purpose | **NO** — blocked (correct) |

**The worker question (foreman-flagged), answered:** the worker is NOT exempted, and that is correct — its writes during the window are exactly the post-snapshot writes a rollback must be able to discard. It does **not** crash-loop (unlike PostgREST it sets no `target_session_attrs`), so its brief step-11→completion window under read-only produces at most transient, retried write-failures — not corruption, not health-gating. *(Arc should confirm no worker crash-loop; the mechanism says it won't.)*

## What can write during the window, after the fix
- **Intended writers:** the upgrade's own `migrate` + service connection (as before).
- **PostgREST (authenticator):** write-*capable* at the DB level, but externally frozen by the maintenance 503 — effectively read-only from outside.
- **Frozen (correct):** the worker, the app role, and every direct-PG integrator role. A rollback still loses nothing external.

## Crash mid-window, after the fix
With the migration applied and a crash mid-phase-3: database read-only stays `on` (crash-freeze intact), authenticator role-GUC stays `off`. On restart, PostgREST comes up **healthy** (listener connects, `/ready` green) while maintenance (Caddy 503) still gates external `/rest` and read-only still gates direct-PG + worker + app. Recovery reads ground truth on its self-exempt conn and decides. Strictly **better** than today (where post-crash PostgREST crash-loops); the external freeze is unchanged.

## Delivery — migration (recommended) vs alternatives
- **Migration (recommend).** The exemption is a *durable truth* — "authenticator is never subject to the accident-guard, because PostgREST is gated by maintenance, not read-only" — best expressed declaratively in the schema, once, idempotently. It's a no-op outside the window (database default is `off` normally). It applies **within the same upgrade that ships it**: `migrate` (step 10) runs *before* REST restarts (step 11), so the first fix-upgrade heals itself; REST is stopped→restarted around migrate, so no running PostgREST spans the flip. Consistent with how `authenticator` itself is defined (in migrations). Survives crashes.
- **Window ON-step (rejected as primary).** Having `setDatabaseReadOnly(true)` also `ALTER ROLE authenticator … off` is a permanent property masquerading as a per-upgrade toggle — more code, same net effect, worse expressed. Keep the window code purely about the database-GUC.
- **PostgREST-config-side (rejected).** Disabling the notification channel (`PGRST_DB_CHANNEL_ENABLED=false`) removes the `pgrst` NOTIFY channel — which is **load-bearing**: it is how REST reloads its schema cache after DDL, and the dev flow + the **STATBUS-102 channel-bless** flow rely on it. (The upgrade restarts REST anyway, so the upgrade path itself would survive, but disabling it globally degrades hot schema reloads.) Forcing `target_session_attrs=any` isn't cleanly exposed in v12. Version-fragile; do not touch PostgREST config to work around a role-GUC that fixes it precisely.

## Rejected recovery-semantics levers
- **(b) lift read-only before the health check** — reopens the direct-PG hole in the health-check→completion window and **defeats the crash-freeze** (a crash between lift and completion leaves an unfrozen state → rollback no longer data-safe). Reject.
- **(c) any PostgREST-config lever** — see above; fragile, version-specific, breaks notifications.

## Verification (the run is the only oracle)
- **Cheap pre-arc empirical check (do this first, local stack):** `ALTER ROLE authenticator SET default_transaction_read_only = off;` then `ALTER DATABASE statbus_<slot> SET default_transaction_read_only = on;` then restart the `rest` container and poll `/ready` → expect **200** (listener connects). Cleanup: `RESET` both. This confirms empirically that the role-GUC satisfies libpq's read-write probe on the same-db-uri listener — the one claim worth verifying before build.
- Re-run **run 28609876020**'s scenarios; the proof is those upgrade/health-check scenarios going **green** (no PostgREST listener loop, `/ready` 200, upgrade reaches `completed`).
- Assert an external direct-PG write **still** fails read-only mid-window (the guard still holds for non-authenticator roles), and the upgrade's own migrate/service writes still succeed.
- Confirm the worker does **not** crash-loop under read-only (mechanism says it won't; observe it).
- **Tie to STATBUS-054** (PostgREST v12→v14): the listener's connection strategy may change across versions; the role-GUC exemption is version-independent, so it holds through the bump — note it in 054's verification checklist.

## The change set
1. New migration: `ALTER ROLE authenticator SET default_transaction_read_only = off;` (down: `RESET`). Must run after `authenticator` is created (it will — new migration sorts last). *(Shipped vehicle differs — see the DELIVERY STATUS note at top.)*
2. Amend `doc/read-only-upgrade-window.md`: add the authenticator exemption to the invariant + the "Self-exempt" section (the fourth exempt writer, alongside queryConn/migrate), with the maintenance-gates-REST rationale.
3. No change to `setDatabaseReadOnly` or the window ON/OFF placement.
