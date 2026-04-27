-- Migration 20260427124351: drop ensure_collect_changes; merge scheduling into loggers
--
-- Plan section R / task #32 (rc.66 scope, promoted from rc.67):
--
-- Replace the unconditional `worker.ensure_collect_changes()` trigger
-- (fires on every INSERT/UPDATE/DELETE on 14 tracked tables, always
-- sets has_pending=TRUE + enqueues a `collect_changes` task + pg_notify)
-- with scheduling that fires ONLY when the conditional logger
-- (`log_base_change` / `log_region_change`) actually wrote a
-- base_change_log row. Eliminates the over-zealous-trigger false
-- positive observed during seed builds: migrations modify metadata
-- tables, the multirange aggregations come back empty, but the
-- old unconditional trigger spawned a spurious collect_changes task
-- anyway and flipped has_pending=TRUE. After this migration:
--
--   * No unconditional ensure_collect_changes triggers exist.
--   * `worker.ensure_collect_changes()` function is dropped.
--   * `worker.log_base_change()` and `worker.log_region_change()`
--     fold the scheduling block (UPDATE has_pending + INSERT task +
--     pg_notify) into their existing `IF v_*_ids != '{}' THEN ... END IF`
--     conditional INSERT block — same code path as before, just
--     gated by "did we actually log a change row?".
--
-- Specialized variants `worker.ensure_collect_changes_for_legal_relationship`
-- and `worker.ensure_collect_changes_for_power_root` (and their triggers)
-- stay in place — they have additional business logic (early-return
-- when no PG / custom-root assigned) that's not duplicated by the
-- logger-side WHERE filter on every code path. Their scheduling is
-- now harmlessly redundant (ON CONFLICT DO NOTHING dedupes the task,
-- has_pending UPDATE is idempotent, double pg_notify is cheap) and
-- can be cleaned up in a later RC if we audit the equivalence.
--
-- After this lands, the rc.66 seed-drain step in `./dev.sh recreate-seed`
-- (`CALL worker.process_tasks()` after `migrate up --target seed`)
-- becomes a no-op for the spurious task — there's nothing to drain.
-- Left in place as harmless redundancy; cleanup deferred.
BEGIN;

-- ============================================================================
-- Step 1: Drop the 14 unconditional ensure_collect_changes triggers.
-- ============================================================================

DROP TRIGGER IF EXISTS b_activity_ensure_collect             ON public.activity;
DROP TRIGGER IF EXISTS b_contact_ensure_collect              ON public.contact;
DROP TRIGGER IF EXISTS b_enterprise_ensure_collect           ON public.enterprise;
DROP TRIGGER IF EXISTS b_establishment_ensure_collect        ON public.establishment;
DROP TRIGGER IF EXISTS b_external_ident_ensure_collect       ON public.external_ident;
DROP TRIGGER IF EXISTS b_legal_relationship_ensure_collect_delete ON public.legal_relationship;
DROP TRIGGER IF EXISTS b_legal_unit_ensure_collect           ON public.legal_unit;
DROP TRIGGER IF EXISTS b_location_ensure_collect             ON public.location;
DROP TRIGGER IF EXISTS b_person_for_unit_ensure_collect      ON public.person_for_unit;
DROP TRIGGER IF EXISTS b_power_group_ensure_collect          ON public.power_group;
DROP TRIGGER IF EXISTS b_power_root_ensure_collect_delete    ON public.power_root;
DROP TRIGGER IF EXISTS b_region_ensure_collect               ON public.region;
DROP TRIGGER IF EXISTS b_stat_for_unit_ensure_collect        ON public.stat_for_unit;
DROP TRIGGER IF EXISTS b_tag_for_unit_ensure_collect         ON public.tag_for_unit;

-- ============================================================================
-- Step 2: Drop the now-orphan worker.ensure_collect_changes function.
-- ============================================================================

DROP FUNCTION IF EXISTS worker.ensure_collect_changes();

-- ============================================================================
-- Step 3: Augment log_base_change with scheduling inside conditional INSERT.
--
-- Verbatim copy of the prior body (CASE branches for the 13 tracked tables,
-- multirange aggregation, conditional INSERT into worker.base_change_log).
-- The ONLY change: the IF-block at the bottom now also runs the three
-- statements that were in worker.ensure_collect_changes — set has_pending,
-- enqueue collect_changes task (idempotent via ON CONFLICT DO NOTHING),
-- pg_notify the worker.
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.log_base_change()
RETURNS trigger
LANGUAGE plpgsql
AS $log_base_change$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_where_clause TEXT := '';
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_pg_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'person_for_unit' THEN
            -- Temporal table linking person to LU or ES (mutually exclusive).
            -- Has valid_range from sql_saga.
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'tag_for_unit' THEN
            -- Non-temporal table linking tag to any unit type.
            -- Has all four unit ID columns (exactly one non-NULL per row).
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'legal_relationship' THEN
            -- LR changes only affect power groups, not individual LUs/enterprises.
            -- Only log when derived_power_group_id is assigned (NULL = PG not yet linked).
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, derived_power_group_id AS pg_id';
            v_has_valid_range := TRUE;

            v_where_clause := ' WHERE derived_power_group_id IS NOT NULL';
        WHEN 'power_group' THEN
            -- PG metadata changes (name, type_id, etc.) affect PG statistical units.
            -- Timeless table — no valid_range.
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, id AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'power_root' THEN
            -- PR changes (NSO custom_root override) affect the power group's timeline.
            -- Temporal table — has valid_range.
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := TRUE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    CASE TG_OP
        WHEN 'INSERT' THEN v_source := format('SELECT %s FROM new_rows%s', v_columns, v_where_clause);
        WHEN 'DELETE' THEN v_source := format('SELECT %s FROM old_rows%s', v_columns, v_where_clause);
        WHEN 'UPDATE' THEN v_source := format('SELECT %s FROM old_rows%s UNION ALL SELECT %s FROM new_rows%s', v_columns, v_where_clause, v_columns, v_where_clause);
        ELSE RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- No UNION ALL for influenced_id — LR changes only log PG IDs, not individual LU IDs

    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(pg_id, pg_id, %1$L)) FILTER (WHERE pg_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range);

        -- Folded from former worker.ensure_collect_changes (rc.66, task #32):
        -- scheduling now fires only when actual change data was logged,
        -- not unconditionally on every metadata write.
        UPDATE worker.base_change_log_has_pending
        SET has_pending = TRUE WHERE has_pending = FALSE;

        -- Enqueue collect_changes task (DO NOTHING = no row lock!).
        INSERT INTO worker.tasks (command, payload)
        VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
        ON CONFLICT (command)
        WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
        DO NOTHING;

        -- pg_notify fires even when ON CONFLICT DO NOTHING matches (PG provides
        -- no way to detect this). Cost is negligible: worker wakes, finds nothing, sleeps.
        PERFORM pg_notify('worker_tasks', 'analytics');
    END IF;

    RETURN NULL;
END;
$log_base_change$;

-- ============================================================================
-- Step 4: Augment log_region_change with the same scheduling fold.
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.log_region_change()
RETURNS trigger
LANGUAGE plpgsql
AS $log_region_change$
DECLARE
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_valid_ranges datemultirange;
    v_source TEXT;
BEGIN
    -- Build source query based on operation
    CASE TG_OP
        WHEN 'INSERT' THEN v_source := 'new_rows';
        WHEN 'DELETE' THEN v_source := 'old_rows';
        WHEN 'UPDATE' THEN v_source := 'old_rows UNION ALL SELECT * FROM new_rows';
        ELSE RAISE EXCEPTION 'log_region_change: unsupported operation %', TG_OP;
    END CASE;

    -- Find affected units by joining region → location
    EXECUTE format(
        $SQL$
        SELECT
            COALESCE(range_agg(int4range(l.establishment_id, l.establishment_id, '[]')) FILTER (WHERE l.establishment_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(int4range(l.legal_unit_id, l.legal_unit_id, '[]')) FILTER (WHERE l.legal_unit_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(l.valid_range) FILTER (WHERE l.valid_range IS NOT NULL), '{}'::datemultirange)
        FROM (%s) AS affected_regions
        JOIN public.location AS l ON l.region_id = affected_regions.id
        $SQL$,
        format('SELECT * FROM %s', v_source)
    ) INTO v_est_ids, v_lu_ids, v_valid_ranges;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, '{}'::int4multirange, '{}'::int4multirange, v_valid_ranges);

        -- Folded from former worker.ensure_collect_changes (rc.66, task #32):
        -- scheduling now fires only when actual change data was logged.
        UPDATE worker.base_change_log_has_pending
        SET has_pending = TRUE WHERE has_pending = FALSE;

        INSERT INTO worker.tasks (command, payload)
        VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
        ON CONFLICT (command)
        WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
        DO NOTHING;

        PERFORM pg_notify('worker_tasks', 'analytics');
    END IF;

    RETURN NULL;
END;
$log_region_change$;

-- ============================================================================
-- Step 5: Drain residual has_pending=TRUE left by the now-dropped triggers.
--
-- During chronological migrate up, the OLD unconditional ensure_collect_changes
-- trigger fired on the 3 tracked-table writes that happen between its creation
-- (migration 20260212123759) and its drop above (Step 1): region/location
-- UPDATEs in 20260312114522 and the external_ident INSERT in 20260312114524.
-- Those firings set has_pending=TRUE and queued spurious collect_changes
-- tasks despite all multiranges being empty (no real units to track yet).
-- Steps 1-4 dropped the over-zealous triggers and replaced them with the
-- conditional fold, but didn't clear the residual flag and tasks.
--
-- worker.process_tasks is the production drain procedure. It checks
-- pg_current_xact_id_if_assigned() and skips its inner COMMITs when called
-- from inside a transaction (this migration's BEGIN/END), so it processes
-- pending tasks but commits everything atomically with the migration.
-- Concurrent worker daemons (in production migrate-up) coordinate via
-- FOR UPDATE SKIP LOCKED — race-safe.
--
-- Net effect: any migrate-up that crosses this migration's boundary leaves
-- has_pending=FALSE and no spurious collect_changes tasks. No build-pipeline
-- drain step needed (recreate-seed in dev.sh stays simple).
-- ============================================================================

CALL worker.process_tasks();

END;
