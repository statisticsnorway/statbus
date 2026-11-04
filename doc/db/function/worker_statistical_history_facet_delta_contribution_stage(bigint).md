```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_contribution_stage(IN p_generation bigint)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    INSERT INTO public.statistical_history_facet_stock_delta_staging
    WITH plus AS (SELECT unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
                         legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
                         exists_delta, countable_delta, stats_delta FROM pg_temp.hd_stock WHERE sign > 0),
         minus AS (SELECT unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
                          legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
                          exists_delta, countable_delta, stats_delta FROM pg_temp.hd_stock WHERE sign < 0)
    SELECT unit_id, 1, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           exists_delta, countable_delta, stats_delta, p_generation
      FROM (SELECT * FROM plus EXCEPT ALL SELECT * FROM minus) AS a
    UNION ALL
    SELECT unit_id, -1, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           -exists_delta, -countable_delta, public.jsonb_stats_negate(stats_delta), p_generation
      FROM (SELECT * FROM minus EXCEPT ALL SELECT * FROM plus) AS r;

    INSERT INTO public.statistical_history_facet_flow_delta_staging
    WITH plus AS (SELECT unit_id, resolution, year, month, unit_type, primary_activity_category_path,
                         secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
                         physical_country_id, unit_size_id, status_id, flows, stats_ended FROM pg_temp.hd_flow WHERE sign > 0),
         minus AS (SELECT unit_id, resolution, year, month, unit_type, primary_activity_category_path,
                          secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
                          physical_country_id, unit_size_id, status_id, flows, stats_ended FROM pg_temp.hd_flow WHERE sign < 0)
    SELECT unit_id, 1, resolution, year, month, unit_type, primary_activity_category_path,
           secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
           physical_country_id, unit_size_id, status_id, flows, stats_ended, p_generation
      FROM (SELECT * FROM plus EXCEPT ALL SELECT * FROM minus) AS a
    UNION ALL
    SELECT unit_id, -1, resolution, year, month, unit_type, primary_activity_category_path,
           secondary_activity_category_path, sector_path, legal_form_id, physical_region_path,
           physical_country_id, unit_size_id, status_id,
           (SELECT array_agg(-f ORDER BY i) FROM unnest(flows) WITH ORDINALITY AS z(f, i)),
           public.jsonb_stats_negate(stats_ended), p_generation
      FROM (SELECT * FROM minus EXCEPT ALL SELECT * FROM plus) AS r;
    TRUNCATE pg_temp.hd_stock, pg_temp.hd_flow;
END;
$procedure$
```
