```sql
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
```
