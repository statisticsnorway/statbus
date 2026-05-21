# Migration Call-Tree Prohibition

## The rule

**Migrations MUST NOT call any function or worker-task command in the `collect_changes` transitive closure directly.** Anything downstream of `collect_changes` is worker-pipeline-only.

The only correct way to schedule work in this tree from a migration is the EXISTS-guarded `worker.spawn('collect_changes', ...) + pg_notify` block (the canonical "trigger the base change, let the worker flush it" pattern). The EXISTS guard isn't optional — it's what keeps the seed/test_template fixtures clean (empty base tables → no spawn → no phantom task in `pg_dump`).

## Why

Functions in the tree have side effects (chunking, parallelism, dirty-set tracking, structured concurrency) that depend on running inside a worker-task child, not inside a migration's transaction:

- They scale linearly with data size when called from the worker pipeline (chunked via `get_temporally_closed_change_sets`); they scale catastrophically when called synchronously from a migration on production-scale data.
- They write to `worker.tasks`, `worker.base_change_log_has_pending`, `statistical_unit_facet_dirty_hash_slots`, etc. — state that's expected to be transient and worker-managed, not migration-frozen.
- They take time. A migration calling them synchronously blocks the entire upgrade pipeline (incl. systemd's `TimeoutStartSec`), often invisibly.

The 2026-05-21 incident: migration `20260521112759_fix_statistical_history_facet_indexes` called `SELECT public.statistical_history_facet_derive('-infinity', 'infinity')` directly. On dev (8k facet rows) the upgrade-service systemd unit was killed after 90s and entered a 76-iteration kill-restart loop. On production-scale slots it would never complete.

## The closure (computed from live DB, 2026-05-21)

Source: `worker.command_registry` → `worker.command_collect_changes` body → recursive `worker.spawn(p_command, ...)` extraction.

### Worker task commands (12, including `collect_changes` itself)

These map 1:1 to handler procedures in `worker.command_registry`. A migration that does `INSERT INTO worker.tasks (command, ...) VALUES ('<X>', ...)` or `PERFORM worker.spawn(p_command => '<X>', ...)` for any command in this list — EXCEPT `collect_changes` via the EXISTS-guarded canonical pattern — is wrong.

| Task command | Handler procedure |
|---|---|
| `collect_changes` | `worker.command_collect_changes` |
| `derive_units_phase` | `worker.derive_units_phase` |
| `derive_statistical_unit` | `worker.derive_statistical_unit` |
| `statistical_unit_flush_staging` | `worker.statistical_unit_flush_staging` |
| `derive_used_tables` | `worker.derive_used_tables` |
| `derive_reports_phase` | `worker.derive_reports_phase` |
| `derive_statistical_history` | `worker.derive_statistical_history` |
| `statistical_history_reduce` | `worker.statistical_history_reduce` |
| `derive_statistical_unit_facet` | `worker.derive_statistical_unit_facet` |
| `statistical_unit_facet_reduce` | `worker.statistical_unit_facet_reduce` |
| `derive_statistical_history_facet` | `worker.derive_statistical_history_facet` |
| `statistical_history_facet_reduce` | `worker.statistical_history_facet_reduce` |

### PG functions in the tree (must not be called from a migration)

These are the "machine room" functions that the handlers dispatch to. Calling any of them directly from a migration (via `SELECT`, `PERFORM`, `CALL`, or `EXECUTE`) is the failure mode that bit us on 2026-05-21.

- `public.statistical_history_facet_derive` ← **today's culprit**
- `public.statistical_history_derive`
- `public.statistical_unit_facet_derive`
- `public.statistical_unit_flush_staging`
- `public.activity_category_used_derive`
- `public.country_used_derive`
- `public.data_source_used_derive`
- `public.legal_form_used_derive`
- `public.region_used_derive`
- `public.sector_used_derive`

## The required pattern (the solution)

Inside a migration's `BEGIN; ... COMMIT;` block, use this exact shape to trigger a full rebuild:

```sql
DO $name$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.establishment
        UNION ALL SELECT 1 FROM public.legal_unit
        UNION ALL SELECT 1 FROM public.enterprise
        UNION ALL SELECT 1 FROM public.power_group
        LIMIT 1
    ) THEN
        PERFORM worker.spawn(
            p_command => 'collect_changes',
            p_payload => jsonb_build_object(
                'establishment_id_ranges', NULL,
                'legal_unit_id_ranges',    NULL,
                'enterprise_id_ranges',    NULL,
                'power_group_id_ranges',   NULL,
                'valid_ranges',            NULL
            )
        );
        PERFORM pg_notify('worker_tasks', 'analytics');
    END IF;
END
$name$;
```

Why each element is load-bearing:
- **EXISTS guard on the four base tables** — fresh seed/test_template fixtures have empty base tables → spawn skipped → seed dump captures zero pending tasks → no test baseline drift.
- **`collect_changes` with NULL id-ranges** — the handler synthesises full id-sets from base tables at spawn-time → drives a chunked rebuild through the existing worker pipeline → feasible at production scale.
- **`pg_notify('worker_tasks', 'analytics')`** — wakes the worker daemon immediately instead of waiting for the 30s idle tick.
- **Migration commits fast** — schema + data state stay atomic; the rebuild runs asynchronously post-commit via the worker.

## Precedents

- **`migrations/20260520204526_fix_derive_statistical_unit_orphan_dirty_hash_slots.up.sql:297-372`** — full inline documentation of the pattern + its constraints.
- **`migrations/20260422000000_rc42_post_upgrade_rebuild.up.sql`** (BLOCK F) — first occurrence.

## Rare exception

The only legitimate reason to call a tree function directly from a migration is if the function is being MODIFIED in the same migration (`CREATE OR REPLACE FUNCTION ...`). That's a function DEFINITION, not a CALL — different thing. A definition is fine; a call from a top-level `SELECT` / `PERFORM` / `CALL` / `DO` statement is not.

If the operator believes they truly need a direct call (extremely rare), the override mechanism is to annotate the call:

```sql
-- @migrate: explicit-tree-call <reason>
SELECT public.statistical_history_facet_derive(...);
```

The lint (task #82) will log the bypass with the justification.

## Maintaining this list

The closure is computable from the live database — there's no need to hand-maintain the list. Regenerate when the worker pipeline changes:

```bash
# 1. Get the entry point handler.
echo "SELECT handler_procedure FROM worker.command_registry WHERE command = 'collect_changes'" | ./sb psql

# 2. Walk the worker.spawn calls in each handler.
echo "\sf worker.command_collect_changes" | ./sb psql | grep -A1 "p_command =>"

# 3. For each spawned command, look up its handler:
echo "SELECT command, handler_procedure FROM worker.command_registry WHERE command IN (...)" | ./sb psql

# 4. Walk each handler for further spawn calls; add to set; repeat to fixed point.

# 5. PG functions: enumerate by naming convention (workpipeline functions all end in _derive, _reduce, _flush_staging):
echo "SELECT n.nspname||'.'||p.proname FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE p.proname ~ '(_derive|_reduce|_flush_staging|^command_|_used_derive)$'" | ./sb psql
```

The lint implementation in task #82 will automate this and cache the result keyed on the seed fingerprint.

## Cross-link

- Task #78 — lift the EXISTS-guarded backfill pattern to top-level doc (this file is part of that lift).
- Task #82 — implement the structural lint that enforces this prohibition automatically.
- Today's incident: `tmp/seed-race-audit.md` (different incident, same migration).
- 2026-05-21 outage: dev's 76-iteration kill-restart loop on `20260521112759`.
