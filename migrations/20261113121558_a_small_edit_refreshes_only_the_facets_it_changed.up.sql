-- Migration 20261113121558: a small edit refreshes only the facets it changed (STATBUS-626).
--
-- worker.statistical_unit_facet_reduce merged public.statistical_unit_facet from the aggregate of
-- all of public.statistical_unit_facet_staging after every cycle, so a three-unit edit regrouped
-- three million staging rows (11-16 s of an 18-24 s edit on the Norway register). A unit's staging
-- rows sit in its own hash slot, and a partial cycle marks the slots of the units it changed dirty
-- (public.statistical_unit_facet_dirty_hash_slots), so only the facet keys staged in those slots
-- can change: the keys there before the rewrite (where the units' counts leave) and after it
-- (where they arrive). The reduce now recounts just those keys. The children rewrite whole
-- 64-slot ranges, but the other slots of a range hold unchanged units and the same rows again;
-- recounting the keys of whole ranges took 49,406 keys for a three-unit edit, its nine dirty
-- slots hold 1,561.
--
-- What the reduce must recount is kept until a reduce commits: the dirty slots and whether every
-- facet must be recounted (worker.statistical_unit_facet_state), and the keys staged in those
-- slots before the rewrite (worker.statistical_unit_facet_recount_keys). A derive only adds to them.
-- The scoped reduce of April 2026 (20260422000000) emptied its before-snapshot at every derive,
-- so a cycle whose reduce failed lost the facets its units had left, and they stayed counted
-- (20260429233218 collapsed the reduce to a whole-table MERGE).
BEGIN;

CREATE TABLE worker.statistical_unit_facet_state (
    recount_all boolean NOT NULL DEFAULT true,
    recount_slots integer[] NOT NULL DEFAULT '{}'
);
CREATE UNIQUE INDEX statistical_unit_facet_state_single_row ON worker.statistical_unit_facet_state ((true));
-- recount_all starts true: the first reduce after this migration recounts every facet, as before.
INSERT INTO worker.statistical_unit_facet_state DEFAULT VALUES;
COMMENT ON TABLE worker.statistical_unit_facet_state IS
'One row: what worker.statistical_unit_facet_reduce must recount, set by worker.derive_statistical_unit_facet and reset by the reduce that recounts it, in the reduce''s transaction. A derive only adds to it, so the work of a cycle whose reduce did not commit is done by the next reduce.';
COMMENT ON COLUMN worker.statistical_unit_facet_state.recount_all IS
'Every facet must be recounted: a derive rewrote all of public.statistical_unit_facet_staging (a full recalculation, or staging found empty), and no reduce has committed since.';
COMMENT ON COLUMN worker.statistical_unit_facet_state.recount_slots IS
'Dirty hash slots of the partial derives since the last reduce committed: the slots of the units those cycles changed. The facet keys staged in them now are the facets the units entered; worker.statistical_unit_facet_recount_keys holds the ones they left.';

CREATE UNLOGGED TABLE worker.statistical_unit_facet_recount_keys (
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    valid_until date NOT NULL,
    unit_type public.statistical_unit_type NOT NULL,
    physical_region_path public.ltree,
    primary_activity_category_path public.ltree,
    sector_path public.ltree,
    legal_form_id integer,
    physical_country_id integer,
    status_id integer
);
COMMENT ON TABLE worker.statistical_unit_facet_recount_keys IS
'Facet keys staged in the dirty hash slots of a partial derive, recorded by worker.derive_statistical_unit_facet before its children rewrite them: the facets the changed units may leave. worker.statistical_unit_facet_reduce recounts them and empties the table in its transaction. UNLOGGED like the staging it describes: after a crash staging is empty too, and the next derive rewrites all of it (worker.statistical_unit_facet_state.recount_all).';

-- The reduce recounts a key from every staging row that has it, in any hash slot. The key columns
-- are matched as the facet table's unique key matches them (NULLS NOT DISTINCT), through the
-- COALESCE forms below, so each column is an index condition.
CREATE INDEX statistical_unit_facet_staging_key_idx ON public.statistical_unit_facet_staging
    (valid_from, valid_to, valid_until, unit_type,
     (COALESCE(physical_region_path::text, '')), (COALESCE(primary_activity_category_path::text, '')),
     (COALESCE(sector_path::text, '')), (COALESCE(legal_form_id, -1)),
     (COALESCE(physical_country_id, -1)), (COALESCE(status_id, -1)));
COMMENT ON INDEX public.statistical_unit_facet_staging_key_idx IS
'Finds every staging row of a facet key, in any hash slot, for the recount in worker.statistical_unit_facet_reduce. The expressions are the ones that procedure joins on.';

-- The scoped reduce finds the stored facet of each recounted key, in its MERGE and its DELETE.
CREATE INDEX statistical_unit_facet_key_idx ON public.statistical_unit_facet
    (valid_from, valid_to, (COALESCE(valid_until, 'infinity'::date)), unit_type,
     (COALESCE(physical_region_path::text, '')), (COALESCE(primary_activity_category_path::text, '')),
     (COALESCE(sector_path::text, '')), (COALESCE(legal_form_id, -1)),
     (COALESCE(physical_country_id, -1)), (COALESCE(status_id, -1)));
COMMENT ON INDEX public.statistical_unit_facet_key_idx IS
'Finds the stored facet of a key for the scoped recount in worker.statistical_unit_facet_reduce (its MERGE and DELETE). The expressions are the ones that procedure matches on.';

CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_hash_slots integer[];
    v_child_count integer := 0;
    v_partition_count_target integer;
    v_hash_partition_size integer;
    v_hash_partition int4range;
    v_left_keys bigint := 0;
BEGIN
    v_partition_count_target := public.get_partition_count_target();
    v_hash_partition_size := GREATEST(1, 16384 / v_partition_count_target);

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(dirty_hash_slot ORDER BY dirty_hash_slot) INTO v_dirty_hash_slots
    FROM public.statistical_unit_facet_dirty_hash_slots;

    -- Full rebuild when the request covers all time, valid_from = -infinity
    -- and valid_until = infinity (STATBUS-538, see
    -- worker.enqueue_derive_statistical_unit_all), or when the staging cache
    -- is empty (fresh install, unclean shutdown of the UNLOGGED table). A
    -- full rebuild drops the whole cache first: slots whose units no longer
    -- exist are never dirty and would otherwise keep counting in the reduce.
    IF v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date THEN
        DELETE FROM public.statistical_unit_facet_staging WHERE true; -- every row: a full-range derive rebuilds all staging
        v_dirty_hash_slots := NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM public.statistical_unit_facet_staging LIMIT 1) THEN
        v_dirty_hash_slots := NULL;
    END IF;

    IF v_dirty_hash_slots IS NOT NULL THEN
        IF cardinality(v_dirty_hash_slots) > 16384 / 16 THEN
            -- A large change: its dirty slots' keys cover most facets, and one pass over all
            -- staging recounts them faster than a lookup per key (worker.statistical_unit_facet_reduce).
            UPDATE worker.statistical_unit_facet_state
               SET recount_all = true, recount_slots = '{}'
             WHERE NOT recount_all OR recount_slots <> '{}';
            DELETE FROM worker.statistical_unit_facet_recount_keys WHERE true; -- every row: every facet is recounted
        ELSE
            -- The dirty slots, and the facet keys staged in them before the children rewrite them:
            -- the facets the changed units may leave (worker.statistical_unit_facet_state, recount_keys).
            INSERT INTO worker.statistical_unit_facet_recount_keys
            SELECT DISTINCT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                   s.physical_region_path, s.primary_activity_category_path,
                   s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
              FROM public.statistical_unit_facet_staging AS s
             WHERE s.hash_slot = ANY (v_dirty_hash_slots);
            GET DIAGNOSTICS v_left_keys := ROW_COUNT;
            UPDATE worker.statistical_unit_facet_state
               SET recount_slots = ARRAY(SELECT DISTINCT unnest(recount_slots || v_dirty_hash_slots) ORDER BY 1)
             WHERE NOT recount_all;
        END IF;

        -- One child per partition range holding a dirty slot, the same ranges
        -- as the full rebuild (STATBUS-543).
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (d.slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((d.slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM unnest(v_dirty_hash_slots) AS d(slot)
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        -- All staging is rewritten, so every facet is recounted.
        UPDATE worker.statistical_unit_facet_state
           SET recount_all = true, recount_slots = '{}'
         WHERE NOT recount_all OR recount_slots <> '{}';
        DELETE FROM worker.statistical_unit_facet_recount_keys WHERE true; -- every row: every facet is recounted
        FOR v_hash_partition IN
            SELECT DISTINCT int4range(
                (su.hash_slot / v_hash_partition_size) * v_hash_partition_size,
                LEAST((su.hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384)
            )
            FROM public.statistical_unit AS su
            WHERE su.used_for_counting
            ORDER BY 1
        LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'hash_partition', v_hash_partition::text
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    p_info := jsonb_build_object('child_count', v_child_count, 'left_keys', v_left_keys);
END;
$procedure$;

COMMENT ON PROCEDURE worker.derive_statistical_unit_facet(jsonb, jsonb) IS
'Rewrites public.statistical_unit_facet_staging: every hash range on a full recalculation (or when staging is empty), else the ranges holding a dirty slot, one derive_statistical_unit_facet_partition child per range. It records for worker.statistical_unit_facet_reduce what to recount: all facets, or the dirty slots together with the keys staged in them before the rewrite (worker.statistical_unit_facet_state, worker.statistical_unit_facet_recount_keys).';

CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_state worker.statistical_unit_facet_state;
    v_row_count bigint;
    v_keys bigint;
    v_deleted bigint;
    v_indexscan text;
    v_bitmapscan text;
BEGIN
    SELECT * INTO v_state FROM worker.statistical_unit_facet_state FOR UPDATE;

    -- A large change touches most facets; then one pass over all staging is cheaper than a
    -- lookup per key (Norway register, 50 % of units: scoped 67 s over every key, global 16-20 s).
    -- At a sixteenth of the slots the keys already cover most facets, so the global MERGE is used.
    IF NOT v_state.recount_all AND cardinality(v_state.recount_slots) > 16384 / 16 THEN
        v_state.recount_all := true;
    END IF;

    IF v_state.recount_all THEN
        -- Every staging row is read, so a hash aggregate over a sequential scan is the plan: walking
        -- the key indexes made for the scoped recount instead took 20-38 s against 15-16 s on the
        -- Norway register. Restored after the MERGE, as the worker may run more in this transaction.
        v_indexscan := current_setting('enable_indexscan');
        v_bitmapscan := current_setting('enable_bitmapscan');
        PERFORM set_config('enable_indexscan', 'off', true);
        PERFORM set_config('enable_bitmapscan', 'off', true);
        MERGE INTO public.statistical_unit_facet AS target
        USING (
            SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                   s.physical_region_path, s.primary_activity_category_path,
                   s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
                   SUM(s.count)::BIGINT AS count,
                   jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
              FROM public.statistical_unit_facet_staging AS s
             GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                      s.physical_region_path, s.primary_activity_category_path,
                      s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
        ) AS source
           ON target.valid_from = source.valid_from
          AND target.valid_to = source.valid_to
          AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND (target.count <> source.count
                          OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET count = source.count,
                            stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                         physical_region_path, primary_activity_category_path,
                         sector_path, legal_form_id, physical_country_id, status_id,
                         count, stats_summary)
                 VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                         source.physical_region_path, source.primary_activity_category_path,
                         source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                         source.count, source.stats_summary)
        WHEN NOT MATCHED BY SOURCE THEN DELETE;
        GET DIAGNOSTICS v_row_count := ROW_COUNT;
        PERFORM set_config('enable_indexscan', v_indexscan, true);
        PERFORM set_config('enable_bitmapscan', v_bitmapscan, true);

        p_info := jsonb_build_object('mode', 'global', 'rows_merged', v_row_count);
    ELSE
        -- The facets the cycles since the last committed reduce can have changed: the keys their
        -- units left (recorded before the rewrite) and the keys now staged in their dirty slots.
        IF to_regclass('pg_temp.facet_keys') IS NOT NULL THEN DROP TABLE facet_keys; END IF;
        CREATE TEMP TABLE facet_keys ON COMMIT DROP AS
        SELECT k.valid_from, k.valid_to, k.valid_until, k.unit_type,
               COALESCE(k.physical_region_path::text, '') AS region, COALESCE(k.primary_activity_category_path::text, '') AS activity,
               COALESCE(k.sector_path::text, '') AS sector, COALESCE(k.legal_form_id, -1) AS legal_form,
               COALESCE(k.physical_country_id, -1) AS country, COALESCE(k.status_id, -1) AS status
          FROM worker.statistical_unit_facet_recount_keys AS k
        UNION
        SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               COALESCE(s.physical_region_path::text, ''), COALESCE(s.primary_activity_category_path::text, ''),
               COALESCE(s.sector_path::text, ''), COALESCE(s.legal_form_id, -1),
               COALESCE(s.physical_country_id, -1), COALESCE(s.status_id, -1)
          FROM public.statistical_unit_facet_staging AS s
         WHERE s.hash_slot = ANY (v_state.recount_slots);
        GET DIAGNOSTICS v_keys := ROW_COUNT;
        ANALYZE facet_keys;

        MERGE INTO public.statistical_unit_facet AS target
        USING (
            SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                   s.physical_region_path, s.primary_activity_category_path,
                   s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
                   SUM(s.count)::BIGINT AS count,
                   jsonb_stats_merge_agg(s.stats_summary) AS stats_summary
              FROM facet_keys AS k
              JOIN public.statistical_unit_facet_staging AS s
                ON s.valid_from = k.valid_from AND s.valid_to = k.valid_to
               AND s.valid_until = k.valid_until AND s.unit_type = k.unit_type
               AND COALESCE(s.physical_region_path::text, '') = k.region
               AND COALESCE(s.primary_activity_category_path::text, '') = k.activity
               AND COALESCE(s.sector_path::text, '') = k.sector
               AND COALESCE(s.legal_form_id, -1) = k.legal_form
               AND COALESCE(s.physical_country_id, -1) = k.country
               AND COALESCE(s.status_id, -1) = k.status
             GROUP BY s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                      s.physical_region_path, s.primary_activity_category_path,
                      s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
        ) AS source
           ON target.valid_from = source.valid_from
          AND target.valid_to = source.valid_to
          AND COALESCE(target.valid_until, 'infinity'::date) = COALESCE(source.valid_until, 'infinity'::date)
          AND target.unit_type = source.unit_type
          AND COALESCE(target.physical_region_path::text, '') = COALESCE(source.physical_region_path::text, '')
          AND COALESCE(target.primary_activity_category_path::text, '') = COALESCE(source.primary_activity_category_path::text, '')
          AND COALESCE(target.sector_path::text, '') = COALESCE(source.sector_path::text, '')
          AND COALESCE(target.legal_form_id, -1) = COALESCE(source.legal_form_id, -1)
          AND COALESCE(target.physical_country_id, -1) = COALESCE(source.physical_country_id, -1)
          AND COALESCE(target.status_id, -1) = COALESCE(source.status_id, -1)
        WHEN MATCHED AND (target.count <> source.count
                          OR target.stats_summary IS DISTINCT FROM source.stats_summary)
            THEN UPDATE SET count = source.count,
                            stats_summary = source.stats_summary
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                         physical_region_path, primary_activity_category_path,
                         sector_path, legal_form_id, physical_country_id, status_id,
                         count, stats_summary)
                 VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                         source.physical_region_path, source.primary_activity_category_path,
                         source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                         source.count, source.stats_summary);
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        -- A recounted facet with no staging row left has lost its last unit.
        DELETE FROM public.statistical_unit_facet AS f
         USING facet_keys AS k
         WHERE f.valid_from = k.valid_from AND f.valid_to = k.valid_to
           AND COALESCE(f.valid_until, 'infinity'::date) = COALESCE(k.valid_until, 'infinity'::date)
           AND f.unit_type = k.unit_type
           AND COALESCE(f.physical_region_path::text, '') = k.region
           AND COALESCE(f.primary_activity_category_path::text, '') = k.activity
           AND COALESCE(f.sector_path::text, '') = k.sector
           AND COALESCE(f.legal_form_id, -1) = k.legal_form
           AND COALESCE(f.physical_country_id, -1) = k.country
           AND COALESCE(f.status_id, -1) = k.status
           AND NOT EXISTS (
               SELECT 1 FROM public.statistical_unit_facet_staging AS s
                WHERE s.valid_from = k.valid_from AND s.valid_to = k.valid_to
                  AND s.valid_until = k.valid_until AND s.unit_type = k.unit_type
                  AND COALESCE(s.physical_region_path::text, '') = k.region
                  AND COALESCE(s.primary_activity_category_path::text, '') = k.activity
                  AND COALESCE(s.sector_path::text, '') = k.sector
                  AND COALESCE(s.legal_form_id, -1) = k.legal_form
                  AND COALESCE(s.physical_country_id, -1) = k.country
                  AND COALESCE(s.status_id, -1) = k.status);
        GET DIAGNOSTICS v_deleted := ROW_COUNT;

        p_info := jsonb_build_object('mode', 'scoped', 'keys_recounted', v_keys,
                                     'rows_merged', v_row_count, 'rows_deleted', v_deleted);
    END IF;

    -- Recounted: what the derives recorded is settled in this transaction.
    UPDATE worker.statistical_unit_facet_state
       SET recount_all = false, recount_slots = '{}'
     WHERE recount_all OR recount_slots <> '{}';
    DELETE FROM worker.statistical_unit_facet_recount_keys WHERE true; -- every row: each was recounted above
END;
$procedure$;

COMMENT ON PROCEDURE worker.statistical_unit_facet_reduce(jsonb, jsonb) IS
'Keeps public.statistical_unit_facet equal to the facet counts over public.statistical_unit_facet_staging, recounting what worker.statistical_unit_facet_state records. After a full rewrite of staging it merges the whole staging aggregate (mode global). Otherwise it recounts only the keys the cycles since the last committed reduce can have changed: worker.statistical_unit_facet_recount_keys (the facets their units left) together with the keys now staged in their dirty slots (the facets they entered); a recounted key with no staging row is deleted (mode scoped). An edit moves a unit''s count out of some facets and into others, so both sides are needed.';

END;
