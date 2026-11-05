```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_contribution_stage(IN p_generation bigint)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    INSERT INTO public.statistical_history_facet_delta_staging (unit_id, sign, unit_type, primary_activity_category_path,
           secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id,
           unit_size_id, status_id, on_month, exists_added_count, exists_removed_count, countable_added_count,
           countable_removed_count, exists_moved_in_count, exists_moved_out_count, countable_moved_in_count,
           countable_moved_out_count, births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year, generation)
    WITH plus AS (SELECT unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
           exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
           births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year
                    FROM pg_temp.hd_rows WHERE sign > 0),
         minus AS (SELECT unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
           exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
           births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year
                     FROM pg_temp.hd_rows WHERE sign < 0),
         added AS (SELECT * FROM plus EXCEPT ALL SELECT * FROM minus),
         removed AS (SELECT * FROM minus EXCEPT ALL SELECT * FROM plus)
    SELECT unit_id, 1, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
           exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
           births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year, p_generation
      FROM added
    UNION ALL
    SELECT unit_id, -1, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
           legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           -exists_added_count, -exists_removed_count, -countable_added_count, -countable_removed_count,
           -exists_moved_in_count, -exists_moved_out_count, -countable_moved_in_count, -countable_moved_out_count,
           -births, -deaths, -name_change_count, -primary_activity_category_change_count,
           -secondary_activity_category_change_count, -sector_change_count, -legal_form_change_count,
           -physical_region_change_count, -physical_country_change_count, -physical_address_change_count,
           -unit_size_change_count, -status_change_count, public.jsonb_stats_negate(stats_delta),
           public.jsonb_stats_negate(stats_ended_month), public.jsonb_stats_negate(stats_ended_year), p_generation
      FROM removed;
    TRUNCATE pg_temp.hd_rows;
END;
$procedure$
```
