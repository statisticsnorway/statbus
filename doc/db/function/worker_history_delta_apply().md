```sql
CREATE OR REPLACE PROCEDURE worker.history_delta_apply()
 LANGUAGE plpgsql
 SET enable_mergejoin TO 'off'
AS $procedure$
BEGIN
    LOCK TABLE public.history_stock_delta_staging, public.history_flow_delta_staging IN EXCLUSIVE MODE;

    IF to_regclass('pg_temp.hd_sum') IS NOT NULL THEN DROP TABLE pg_temp.hd_sum; END IF;
    CREATE TEMP TABLE hd_sum AS
    SELECT unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
           physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           sum(exists_delta)::int AS exists_delta, sum(countable_delta)::int AS countable_delta,
           public.jsonb_stats_delta_agg(stats_delta) FILTER (WHERE stats_delta IS NOT NULL) AS stats_delta,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign > 0) AS plus_ids,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign < 0) AS minus_ids
      FROM public.history_stock_delta_staging
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

    -- The dimensions are nullable, and IS NOT DISTINCT FROM cannot drive a hash join; their row as text
    -- (NULL renders empty, '' renders quoted) is an exact key that can, so the MERGE stays linear.
    MERGE INTO public.history_stock_delta AS t
    USING hd_sum AS s
       ON t.unit_type = s.unit_type AND t.on_month = s.on_month
      AND ROW(t.primary_activity_category_path, t.secondary_activity_category_path, t.sector_path, t.legal_form_id, t.physical_region_path, t.physical_country_id, t.unit_size_id, t.status_id)::text = ROW(s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id)::text
      AND t.primary_activity_category_path IS NOT DISTINCT FROM s.primary_activity_category_path
      AND t.secondary_activity_category_path IS NOT DISTINCT FROM s.secondary_activity_category_path
      AND t.sector_path IS NOT DISTINCT FROM s.sector_path
      AND t.legal_form_id IS NOT DISTINCT FROM s.legal_form_id
      AND t.physical_region_path IS NOT DISTINCT FROM s.physical_region_path
      AND t.physical_country_id IS NOT DISTINCT FROM s.physical_country_id
      AND t.unit_size_id IS NOT DISTINCT FROM s.unit_size_id
      AND t.status_id IS NOT DISTINCT FROM s.status_id
    WHEN MATCHED THEN UPDATE SET
        exists_delta = t.exists_delta + s.exists_delta,
        countable_delta = t.countable_delta + s.countable_delta,
        stats_delta = CASE WHEN t.stats_delta IS NULL THEN s.stats_delta
                           WHEN s.stats_delta IS NULL THEN t.stats_delta
                           ELSE public.jsonb_stats_delta_merge(t.stats_delta, s.stats_delta) END,
        unit_ids = worker.unit_ids_apply(t.unit_ids, s.plus_ids, s.minus_ids)
    WHEN NOT MATCHED THEN INSERT VALUES (s.unit_type, s.primary_activity_category_path, s.secondary_activity_category_path,
        s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id,
        s.on_month, s.exists_delta, s.countable_delta, s.stats_delta, worker.unit_ids_apply('{}', s.plus_ids, s.minus_ids));
    DELETE FROM public.history_stock_delta WHERE cardinality(unit_ids) = 0;

    IF to_regclass('pg_temp.hd_fsum') IS NOT NULL THEN DROP TABLE pg_temp.hd_fsum; END IF;
    CREATE TEMP TABLE hd_fsum AS
    SELECT resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id,
           public.int_array_sum(flows) AS flows,
           public.jsonb_stats_delta_agg(stats_ended) FILTER (WHERE stats_ended IS NOT NULL) AS stats_ended,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign > 0) AS plus_ids,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign < 0) AS minus_ids
      FROM public.history_flow_delta_staging
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12;

    MERGE INTO public.history_flow_delta AS t
    USING hd_fsum AS s
       ON t.resolution = s.resolution AND t.year = s.year AND t.month IS NOT DISTINCT FROM s.month
      AND t.unit_type = s.unit_type
      AND ROW(t.month, t.primary_activity_category_path, t.secondary_activity_category_path, t.sector_path, t.legal_form_id, t.physical_region_path, t.physical_country_id, t.unit_size_id, t.status_id)::text
        = ROW(s.month, s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id)::text
      AND t.primary_activity_category_path IS NOT DISTINCT FROM s.primary_activity_category_path
      AND t.secondary_activity_category_path IS NOT DISTINCT FROM s.secondary_activity_category_path
      AND t.sector_path IS NOT DISTINCT FROM s.sector_path
      AND t.legal_form_id IS NOT DISTINCT FROM s.legal_form_id
      AND t.physical_region_path IS NOT DISTINCT FROM s.physical_region_path
      AND t.physical_country_id IS NOT DISTINCT FROM s.physical_country_id
      AND t.unit_size_id IS NOT DISTINCT FROM s.unit_size_id
      AND t.status_id IS NOT DISTINCT FROM s.status_id
    WHEN MATCHED THEN UPDATE SET
        flows = public.int_array_add(t.flows, s.flows),
        stats_ended = CASE WHEN t.stats_ended IS NULL THEN s.stats_ended
                           WHEN s.stats_ended IS NULL THEN t.stats_ended
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended, s.stats_ended) END,
        unit_ids = worker.unit_ids_apply(t.unit_ids, s.plus_ids, s.minus_ids)
    WHEN NOT MATCHED THEN INSERT VALUES (s.resolution, s.year, s.month, s.unit_type, s.primary_activity_category_path,
        s.secondary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path,
        s.physical_country_id, s.unit_size_id, s.status_id, s.flows, s.stats_ended,
        worker.unit_ids_apply('{}', s.plus_ids, s.minus_ids));
    DELETE FROM public.history_flow_delta WHERE cardinality(unit_ids) = 0;

    TRUNCATE public.history_stock_delta_staging, public.history_flow_delta_staging;
END;
$procedure$
```
