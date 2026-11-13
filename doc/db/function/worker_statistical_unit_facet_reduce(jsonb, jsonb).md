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
$procedure$
```
