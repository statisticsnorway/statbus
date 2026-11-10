```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_apply(IN p_replace boolean DEFAULT false)
 LANGUAGE plpgsql
 SET enable_mergejoin TO 'off'
AS $procedure$
DECLARE
    v_up_to bigint := (SELECT flushed_generation FROM worker.statistical_history_facet_delta_state);
BEGIN
    LOCK TABLE public.statistical_history_facet_delta_staging IN EXCLUSIVE MODE;
    IF p_replace THEN
        DELETE FROM public.statistical_history_facet_delta WHERE true; -- every row: p_replace rebuilds the delta table
    END IF;

    IF to_regclass('pg_temp.hd_sum') IS NOT NULL THEN DROP TABLE pg_temp.hd_sum; END IF;
    CREATE TEMP TABLE hd_sum AS
    SELECT unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
           physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           sum(exists_added_count)::int AS exists_added_count, sum(exists_removed_count)::int AS exists_removed_count,
           sum(countable_added_count)::int AS countable_added_count, sum(countable_removed_count)::int AS countable_removed_count,
           sum(exists_moved_in_count)::int AS exists_moved_in_count, sum(exists_moved_out_count)::int AS exists_moved_out_count,
           sum(countable_moved_in_count)::int AS countable_moved_in_count, sum(countable_moved_out_count)::int AS countable_moved_out_count,
           sum(births)::int AS births, sum(deaths)::int AS deaths, sum(name_change_count)::int AS name_change_count,
           sum(primary_activity_category_change_count)::int AS primary_activity_category_change_count,
           sum(secondary_activity_category_change_count)::int AS secondary_activity_category_change_count,
           sum(sector_change_count)::int AS sector_change_count, sum(legal_form_change_count)::int AS legal_form_change_count,
           sum(physical_region_change_count)::int AS physical_region_change_count,
           sum(physical_country_change_count)::int AS physical_country_change_count,
           sum(physical_address_change_count)::int AS physical_address_change_count,
           sum(unit_size_change_count)::int AS unit_size_change_count, sum(status_change_count)::int AS status_change_count,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_delta)) AS stats_delta,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_ended_month)) AS stats_ended_month,
           public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(stats_ended_year)) AS stats_ended_year,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign > 0) AS plus_ids,
           array_agg(unit_id ORDER BY unit_id) FILTER (WHERE sign < 0) AS minus_ids
      FROM public.statistical_history_facet_delta_staging
     WHERE generation <= v_up_to
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;

    -- The dimensions are nullable, and IS NOT DISTINCT FROM cannot drive a hash join; their row as text
    -- (NULL renders empty, '' renders quoted) is an exact key that can, so the MERGE stays linear.
    MERGE INTO public.statistical_history_facet_delta AS t
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
        exists_added_count = t.exists_added_count + s.exists_added_count,
        exists_removed_count = t.exists_removed_count + s.exists_removed_count,
        countable_added_count = t.countable_added_count + s.countable_added_count,
        countable_removed_count = t.countable_removed_count + s.countable_removed_count,
        exists_moved_in_count = t.exists_moved_in_count + s.exists_moved_in_count,
        exists_moved_out_count = t.exists_moved_out_count + s.exists_moved_out_count,
        countable_moved_in_count = t.countable_moved_in_count + s.countable_moved_in_count,
        countable_moved_out_count = t.countable_moved_out_count + s.countable_moved_out_count,
        births = t.births + s.births,
        deaths = t.deaths + s.deaths,
        name_change_count = t.name_change_count + s.name_change_count,
        primary_activity_category_change_count = t.primary_activity_category_change_count + s.primary_activity_category_change_count,
        secondary_activity_category_change_count = t.secondary_activity_category_change_count + s.secondary_activity_category_change_count,
        sector_change_count = t.sector_change_count + s.sector_change_count,
        legal_form_change_count = t.legal_form_change_count + s.legal_form_change_count,
        physical_region_change_count = t.physical_region_change_count + s.physical_region_change_count,
        physical_country_change_count = t.physical_country_change_count + s.physical_country_change_count,
        physical_address_change_count = t.physical_address_change_count + s.physical_address_change_count,
        unit_size_change_count = t.unit_size_change_count + s.unit_size_change_count,
        status_change_count = t.status_change_count + s.status_change_count,
        stats_delta = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_delta IS NULL THEN s.stats_delta
                           WHEN s.stats_delta IS NULL THEN t.stats_delta
                           ELSE public.jsonb_stats_delta_merge(t.stats_delta, s.stats_delta) END),
        stats_ended_month = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_ended_month IS NULL THEN s.stats_ended_month
                           WHEN s.stats_ended_month IS NULL THEN t.stats_ended_month
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended_month, s.stats_ended_month) END),
        stats_ended_year = public.jsonb_stats_delta_nullif_zero(CASE WHEN t.stats_ended_year IS NULL THEN s.stats_ended_year
                           WHEN s.stats_ended_year IS NULL THEN t.stats_ended_year
                           ELSE public.jsonb_stats_delta_merge(t.stats_ended_year, s.stats_ended_year) END),
        unit_ids = worker.unit_ids_apply(t.unit_ids, s.plus_ids, s.minus_ids)
    WHEN NOT MATCHED THEN INSERT (unit_type, primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
        exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
        exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
        births, deaths, name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
        physical_region_change_count, physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year, unit_ids)
      VALUES (s.unit_type, s.primary_activity_category_path, s.secondary_activity_category_path,
        s.sector_path, s.legal_form_id, s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id, s.on_month,
        s.exists_added_count, s.exists_removed_count, s.countable_added_count, s.countable_removed_count,
        s.exists_moved_in_count, s.exists_moved_out_count, s.countable_moved_in_count, s.countable_moved_out_count,
        s.births, s.deaths, s.name_change_count, s.primary_activity_category_change_count,
        s.secondary_activity_category_change_count, s.sector_change_count, s.legal_form_change_count,
        s.physical_region_change_count, s.physical_country_change_count, s.physical_address_change_count,
        s.unit_size_change_count, s.status_change_count, s.stats_delta, s.stats_ended_month, s.stats_ended_year,
        worker.unit_ids_apply('{}', s.plus_ids, s.minus_ids));
    DELETE FROM public.statistical_history_facet_delta WHERE cardinality(unit_ids) = 0;

    IF EXISTS (SELECT 1 FROM public.statistical_history_facet_delta_staging WHERE generation > v_up_to) THEN
        DELETE FROM public.statistical_history_facet_delta_staging WHERE generation <= v_up_to;
    ELSE
        TRUNCATE public.statistical_history_facet_delta_staging;
    END IF;
END;
$procedure$
```
