-- Migration 20261115143155: facet totals follow the changed units by difference (STATBUS-626).
--
-- After a small edit, worker.statistical_unit_facet_reduce (20261113121558) recounted each facet
-- key the changed units left or entered from every staging row with that key, in any hash slot.
-- A popular key (a large region and activity) has rows in thousands of slots, so a three-unit edit
-- on the Norway register recounted 510,000 staging rows for 1,561 keys. The facet summaries are
-- additive (count, sum, sum of squares; jsonb_stats stats_delta), so the reduce now adds to each
-- stored facet the difference its dirty slots made: their staging rows after the rewrite minus
-- their rows before it. That reads only the rows of the dirty slots, before and after.
--
-- min and max cannot be subtracted when a unit leaves, so a facet's stats_summary no longer holds
-- them: it is the stats_agg jsonb_stats_delta_to_agg gives, the merged summary of the facet's units
-- without min and max. Nothing reads facet min or max: the drilldown merges facets and the reports
-- read count and sum. The definition view gives the same form, so the table still equals it.
--
-- The rows before the rewrite are kept per dirty slot in
-- worker.statistical_unit_facet_slot_before, replacing worker.statistical_unit_facet_recount_keys.
-- A slot keeps the rows recorded first until a reduce commits: those are what the stored facets
-- hold. A cycle whose reduce failed leaves its slots recorded, and a later cycle touching the same
-- slot does not record them again.
BEGIN;

-- The first reduce after this migration recounts every facet, in the new form without min/max.
UPDATE worker.statistical_unit_facet_state SET recount_all = true, recount_slots = '{}'
 WHERE NOT recount_all OR recount_slots <> '{}';

DROP TABLE worker.statistical_unit_facet_recount_keys;
CREATE UNLOGGED TABLE worker.statistical_unit_facet_slot_before (
    LIKE public.statistical_unit_facet_staging INCLUDING DEFAULTS
);
CREATE INDEX statistical_unit_facet_slot_before_hash_slot_idx
    ON worker.statistical_unit_facet_slot_before (hash_slot);
COMMENT ON TABLE worker.statistical_unit_facet_slot_before IS
'The staging rows of the dirty hash slots of partial derives as they were before the rewrite, recorded by worker.derive_statistical_unit_facet: what the stored facets hold for those slots. worker.statistical_unit_facet_reduce subtracts them from the facets, adds the slots'' rows after the rewrite, and empties the table in its transaction. A slot already recorded is not recorded again, as its first rows are still what the stored facets hold. UNLOGGED like the staging it copies: after a crash staging is empty too, and the next derive rewrites all of it (worker.statistical_unit_facet_state.recount_all).';
COMMENT ON COLUMN worker.statistical_unit_facet_state.recount_slots IS
'Dirty hash slots of the partial derives since the last reduce committed: the slots of the units those cycles changed. Their staging rows now are the facets the units entered; worker.statistical_unit_facet_slot_before holds their rows before the first rewrite, the ones the stored facets hold.';

-- The reduce no longer looks up staging by facet key: it reads staging by hash slot.
DROP INDEX public.statistical_unit_facet_staging_key_idx;

CREATE OR REPLACE VIEW public.statistical_unit_facet_def
 WITH (security_invoker='on') AS
 SELECT unit_existence_from(valid_from, birth_date) AS valid_from,
    unit_existence_until(valid_until, death_date) - 1 AS valid_to,
    unit_existence_until(valid_until, death_date) AS valid_until,
    unit_type,
    physical_region_path,
    primary_activity_category_path,
    sector_path,
    legal_form_id,
    physical_country_id,
    status_id,
    count(*) AS count,
    jsonb_stats_delta_to_agg(jsonb_stats_to_delta(jsonb_stats_merge_agg(stats_summary))) AS stats_summary
   FROM statistical_unit
  WHERE used_for_counting AND unit_existence_from(valid_from, birth_date) < unit_existence_until(valid_until, death_date)
  GROUP BY (unit_existence_from(valid_from, birth_date)), (unit_existence_until(valid_until, death_date)), unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id
;

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
    v_state worker.statistical_unit_facet_state;
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
            -- A large change: one pass over all staging recounts the facets faster than adding the
            -- differences of this many slots (worker.statistical_unit_facet_reduce).
            UPDATE worker.statistical_unit_facet_state
               SET recount_all = true, recount_slots = '{}'
             WHERE NOT recount_all OR recount_slots <> '{}';
            DELETE FROM worker.statistical_unit_facet_slot_before WHERE true; -- every row: every facet is recounted
        ELSE
            -- The dirty slots' staging rows before the children rewrite them: what the stored facets
            -- hold for those slots (worker.statistical_unit_facet_slot_before). A slot recorded by a
            -- cycle whose reduce has not committed keeps its rows, and a pending recount_all needs none.
            SELECT * INTO v_state FROM worker.statistical_unit_facet_state FOR UPDATE;
            IF NOT v_state.recount_all THEN
                INSERT INTO worker.statistical_unit_facet_slot_before
                SELECT s.*
                  FROM public.statistical_unit_facet_staging AS s
                 WHERE s.hash_slot = ANY (v_dirty_hash_slots)
                   AND s.hash_slot <> ALL (v_state.recount_slots);
                GET DIAGNOSTICS v_left_keys := ROW_COUNT;
            END IF;
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
        DELETE FROM worker.statistical_unit_facet_slot_before WHERE true; -- every row: every facet is recounted
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

    p_info := jsonb_build_object('child_count', v_child_count, 'slot_rows_before', v_left_keys);
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_state worker.statistical_unit_facet_state;
    v_row_count bigint;
    v_keys bigint;
    v_indexscan text;
    v_bitmapscan text;
BEGIN
    SELECT * INTO v_state FROM worker.statistical_unit_facet_state FOR UPDATE;

    -- A large change touches most facets; then one pass over all staging is cheaper than the
    -- difference of each dirty slot (Norway register, 50 % of units: recounting every changed key
    -- 67 s, global 16-20 s). At a sixteenth of the slots the global MERGE is used.
    IF NOT v_state.recount_all AND cardinality(v_state.recount_slots) > 16384 / 16 THEN
        v_state.recount_all := true;
    END IF;

    IF v_state.recount_all THEN
        -- Every staging row is read, so a hash aggregate over a sequential scan is the plan: walking
        -- the facet key index instead took 20-38 s against 15-16 s on the Norway register.
        -- Restored after the MERGE, as the worker may run more in this transaction.
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
                   -- The facet form, without min and max (public.statistical_unit_facet_def).
                   jsonb_stats_delta_to_agg(jsonb_stats_to_delta(jsonb_stats_merge_agg(s.stats_summary))) AS stats_summary
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
        -- What the dirty slots changed in each facet: their staging rows now (the facets their units
        -- are in) minus their rows before the first rewrite since the last committed reduce (the
        -- facets the stored table holds them in, worker.statistical_unit_facet_slot_before). Counts
        -- and summaries are additive (jsonb_stats stats_delta), so a facet is the stored one plus
        -- this difference, and only the rows of the dirty slots are read. A key whose difference
        -- nets to zero, as for a rename, is left as stored.
        IF to_regclass('pg_temp.facet_difference') IS NOT NULL THEN DROP TABLE facet_difference; END IF;
        CREATE TEMP TABLE facet_difference ON COMMIT DROP AS
        SELECT r.valid_from, r.valid_to, r.valid_until, r.unit_type,
               r.physical_region_path, r.primary_activity_category_path,
               r.sector_path, r.legal_form_id, r.physical_country_id, r.status_id,
               SUM(r.count)::BIGINT AS count,
               jsonb_stats_delta_agg(r.stats_delta) AS stats_delta
          FROM (
            SELECT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
                   s.physical_region_path, s.primary_activity_category_path,
                   s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id,
                   s.count, jsonb_stats_to_delta(s.stats_summary) AS stats_delta
              FROM public.statistical_unit_facet_staging AS s
             WHERE s.hash_slot = ANY (v_state.recount_slots)
            UNION ALL
            SELECT b.valid_from, b.valid_to, b.valid_until, b.unit_type,
                   b.physical_region_path, b.primary_activity_category_path,
                   b.sector_path, b.legal_form_id, b.physical_country_id, b.status_id,
                   -b.count, jsonb_stats_negate(b.stats_summary)
              FROM worker.statistical_unit_facet_slot_before AS b
          ) AS r
         GROUP BY r.valid_from, r.valid_to, r.valid_until, r.unit_type,
                  r.physical_region_path, r.primary_activity_category_path,
                  r.sector_path, r.legal_form_id, r.physical_country_id, r.status_id
        HAVING SUM(r.count) <> 0
            OR jsonb_stats_delta_nullif_zero(jsonb_stats_delta_agg(r.stats_delta)) IS NOT NULL;
        GET DIAGNOSTICS v_keys := ROW_COUNT;
        ANALYZE facet_difference;

        MERGE INTO public.statistical_unit_facet AS target
        USING facet_difference AS source
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
        -- The facet's last units left it.
        WHEN MATCHED AND target.count + source.count = 0
            THEN DELETE
        WHEN MATCHED
            THEN UPDATE SET count = target.count + source.count,
                            stats_summary = jsonb_stats_delta_to_agg(
                                jsonb_stats_delta_merge(jsonb_stats_to_delta(target.stats_summary), source.stats_delta))
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (valid_from, valid_to, valid_until, unit_type,
                         physical_region_path, primary_activity_category_path,
                         sector_path, legal_form_id, physical_country_id, status_id,
                         count, stats_summary)
                 VALUES (source.valid_from, source.valid_to, source.valid_until, source.unit_type,
                         source.physical_region_path, source.primary_activity_category_path,
                         source.sector_path, source.legal_form_id, source.physical_country_id, source.status_id,
                         source.count, jsonb_stats_delta_to_agg(source.stats_delta));
        GET DIAGNOSTICS v_row_count := ROW_COUNT;

        p_info := jsonb_build_object('mode', 'difference', 'slots', cardinality(v_state.recount_slots),
                                     'facets_changed', v_keys, 'rows_merged', v_row_count);
    END IF;

    -- Recounted: what the derives recorded is settled in this transaction.
    UPDATE worker.statistical_unit_facet_state
       SET recount_all = false, recount_slots = '{}'
     WHERE recount_all OR recount_slots <> '{}';
    DELETE FROM worker.statistical_unit_facet_slot_before WHERE true; -- every row: each was applied above
END;
$procedure$
;

COMMENT ON PROCEDURE worker.derive_statistical_unit_facet(jsonb, jsonb) IS
'Rewrites public.statistical_unit_facet_staging: every hash range on a full recalculation (or when staging is empty), else the ranges holding a dirty slot, one derive_statistical_unit_facet_partition child per range. It records for worker.statistical_unit_facet_reduce what changed: all facets, or the dirty slots together with their staging rows before the first rewrite since the last committed reduce (worker.statistical_unit_facet_state, worker.statistical_unit_facet_slot_before).';

COMMENT ON PROCEDURE worker.statistical_unit_facet_reduce(jsonb, jsonb) IS
'Keeps public.statistical_unit_facet equal to the facet counts over public.statistical_unit_facet_staging (public.statistical_unit_facet_def), as worker.statistical_unit_facet_state records. After a full rewrite of staging, or a change of more than a sixteenth of the hash slots, it merges the whole staging aggregate (mode global). Otherwise it adds to each stored facet what the dirty slots changed in it: their staging rows now minus their rows before the rewrite (worker.statistical_unit_facet_slot_before). Counts and jsonb_stats summaries are additive, so this is exact, and a facet whose count reaches zero is deleted (mode difference). Facet summaries carry no min or max, which cannot be subtracted.';

COMMENT ON VIEW public.statistical_unit_facet_def IS
'STATBUS-475: facet windows are the unit EXISTENCE window within each record (public.unit_existence_from/until), so the Reports drilldown counts existing units, like the dashboard cards and the Units-over-time chart. stats_summary is the merged summary of the facet''s units without min and max (jsonb_stats_delta_to_agg): worker.statistical_unit_facet_reduce keeps facets by adding and subtracting units, and min and max cannot be subtracted.';

END;
