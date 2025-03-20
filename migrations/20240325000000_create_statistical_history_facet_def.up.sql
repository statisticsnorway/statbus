BEGIN;

SELECT pg_catalog.set_config('search_path', 'public', false);
CREATE VIEW public.statistical_history_facet_def AS
WITH year_with_unit_basis AS (
    SELECT range.resolution AS resolution
         , range.year AS year
         , NULL::INTEGER AS month
         , su_curr.unit_type AS unit_type
         --
         , su_curr.unit_id AS unit_id
         , su_prev.unit_id IS NOT NULL AND su_curr.unit_id IS NOT NULL AS track_changes
         --
         , su_curr.birth_date AS birth_date
         , su_curr.death_date AS death_date
         --
         , COALESCE(range.curr_start <= su_curr.birth_date AND su_curr.birth_date <= range.curr_stop,false) AS born
         , COALESCE(range.curr_start <= su_curr.death_date AND su_curr.death_date <= range.curr_stop,false) AS died
         --
         , su_prev.name                             AS prev_name
         , su_prev.primary_activity_category_path   AS prev_primary_activity_category_path
         , su_prev.secondary_activity_category_path AS prev_secondary_activity_category_path
         , su_prev.sector_path                      AS prev_sector_path
         , su_prev.legal_form_id                    AS prev_legal_form_id
         , su_prev.physical_region_path             AS prev_physical_region_path
         , su_prev.physical_country_id              AS prev_physical_country_id
         , su_prev.physical_address_part1           AS prev_physical_address_part1
         , su_prev.physical_address_part2           AS prev_physical_address_part2
         , su_prev.physical_address_part3           AS prev_physical_address_part3
         --
         , su_prev.status_id                        AS prev_status_id
         , su_prev.status_code                      AS prev_status_code
         --
         , su_curr.name                             AS curr_name
         , su_curr.primary_activity_category_path   AS curr_primary_activity_category_path
         , su_curr.secondary_activity_category_path AS curr_secondary_activity_category_path
         , su_curr.sector_path                      AS curr_sector_path
         , su_curr.legal_form_id                    AS curr_legal_form_id
         , su_curr.physical_region_path             AS curr_physical_region_path
         , su_curr.physical_country_id              AS curr_physical_country_id
         , su_curr.physical_address_part1           AS curr_physical_address_part1
         , su_curr.physical_address_part2           AS curr_physical_address_part2
         , su_curr.physical_address_part3           AS curr_physical_address_part3
         --
         , su_prev.unit_size_id                     AS prev_unit_size_id
         , su_prev.unit_size_code                   AS prev_unit_size_code
         --
         , su_curr.unit_size_id                     AS curr_unit_size_id
         , su_curr.unit_size_code                   AS curr_unit_size_code
         --
         , su_curr.status_id                        AS curr_status_id
         , su_curr.status_code                      AS curr_status_code
         --
         , su_prev.stats AS prev_stats
         , su_curr.stats AS curr_stats
         --
         , su_curr.stats AS stats
         , su_curr.stats_summary AS stats_summary
         --
    FROM public.statistical_history_periods AS range
    JOIN LATERAL (
      -- Within a range find the last row of each timeline
      SELECT *
      FROM (
        SELECT su_range.*
             , ROW_NUMBER() OVER (PARTITION BY su_range.unit_type, su_range.unit_id ORDER BY su_range.valid_from DESC) = 1 AS last_in_range
        FROM public.statistical_unit AS su_range
        WHERE daterange(su_range.valid_from, su_range.valid_to, '[]') && daterange(range.curr_start,range.curr_stop,'[]')
          -- Entries already dead entries are not relevant.
          AND (su_range.death_date IS NULL OR range.curr_start <= su_range.death_date)
          -- Entries not yet born are not relevant.
          AND (su_range.birth_date IS NULL OR su_range.birth_date <= range.curr_stop)
          AND su_range.include_unit_in_reports
      ) AS range_units
      WHERE last_in_range
    ) AS su_curr ON true
    LEFT JOIN public.statistical_unit AS su_prev
      -- There may be a previous entry to compare with.
      ON su_prev.valid_from <= range.prev_stop AND range.prev_stop <= su_prev.valid_to
      AND su_prev.unit_type = su_curr.unit_type AND su_prev.unit_id = su_curr.unit_id
      AND su_prev.include_unit_in_reports
    WHERE range.resolution = 'year'
), year_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND prev_name                             IS DISTINCT FROM curr_name                             AS name_changed
         , track_changes AND NOT born AND not died AND prev_primary_activity_category_path   IS DISTINCT FROM curr_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_secondary_activity_category_path IS DISTINCT FROM curr_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_sector_path                      IS DISTINCT FROM curr_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND prev_legal_form_id                    IS DISTINCT FROM curr_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND prev_physical_region_path             IS DISTINCT FROM curr_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND prev_physical_country_id              IS DISTINCT FROM curr_physical_country_id              AS physical_country_changed
         , track_changes AND NOT born AND not died AND (
                 prev_physical_address_part1 IS DISTINCT FROM curr_physical_address_part1
              OR prev_physical_address_part2 IS DISTINCT FROM curr_physical_address_part2
              OR prev_physical_address_part3 IS DISTINCT FROM curr_physical_address_part3
         ) AS physical_address_changed
         , track_changes AND NOT born AND not died AND prev_unit_size_code IS DISTINCT FROM curr_unit_size_code AS unit_size_code_changed
         , track_changes AND NOT born AND not died AND prev_status_code IS DISTINCT FROM curr_status_code AS status_code_changed
         --
         -- TODO: Track the change in `stats` and put that into `stats_change` using `public.stats_change`.
         --, CASE WHEN track_changes THEN public.stats_change(start_stats,stop_stats) ELSE NULL END AS stats_change
         --
    FROM year_with_unit_basis AS basis
), year_and_month_with_unit_basis AS (
    SELECT range.resolution AS resolution
         , range.year AS year
         , range.month AS month
         , COALESCE(su_prev.unit_type, su_curr.unit_type) AS unit_type
         --
         , su_curr.unit_id AS unit_id
         , su_prev.unit_id IS NOT NULL AND su_curr.unit_id IS NOT NULL AS track_changes
         --
         , su_curr.birth_date AS birth_date
         , su_curr.death_date AS death_date
         --
         , COALESCE(range.curr_start <= su_curr.birth_date AND su_curr.birth_date <= range.curr_stop,false) AS born
         , COALESCE(range.curr_start <= su_curr.death_date AND su_curr.death_date <= range.curr_stop,false) AS died
         --
         , su_prev.name                             AS prev_name
         , su_prev.primary_activity_category_path   AS prev_primary_activity_category_path
         , su_prev.secondary_activity_category_path AS prev_secondary_activity_category_path
         , su_prev.sector_path                      AS prev_sector_path
         , su_prev.legal_form_id                    AS prev_legal_form_id
         , su_prev.physical_region_path             AS prev_physical_region_path
         , su_prev.physical_country_id              AS prev_physical_country_id
         , su_prev.physical_address_part1           AS prev_physical_address_part1
         , su_prev.physical_address_part2           AS prev_physical_address_part2
         , su_prev.physical_address_part3           AS prev_physical_address_part3
         --
         , su_prev.unit_size_id                     AS prev_unit_size_id
         , su_prev.unit_size_code                   AS prev_unit_size_code
         --
         , su_prev.status_id                        AS prev_status_id
         , su_prev.status_code                      AS prev_status_code
         --
         , su_curr.name                             AS curr_name
         , su_curr.primary_activity_category_path   AS curr_primary_activity_category_path
         , su_curr.secondary_activity_category_path AS curr_secondary_activity_category_path
         , su_curr.sector_path                      AS curr_sector_path
         , su_curr.legal_form_id                    AS curr_legal_form_id
         , su_curr.physical_region_path             AS curr_physical_region_path
         , su_curr.physical_country_id              AS curr_physical_country_id
         , su_curr.physical_address_part1           AS curr_physical_address_part1
         , su_curr.physical_address_part2           AS curr_physical_address_part2
         , su_curr.physical_address_part3           AS curr_physical_address_part3
         --
         , su_curr.unit_size_id                     AS curr_unit_size_id
         , su_curr.unit_size_code                   AS curr_unit_size_code
         --
         , su_curr.status_id                        AS curr_status_id
         , su_curr.status_code                      AS curr_status_code
         --
         , su_prev.stats AS prev_stats
         , su_curr.stats AS curr_stats
         --
         , su_curr.stats AS stats
         , su_curr.stats_summary AS stats_summary
         --
    FROM public.statistical_history_periods AS range
    JOIN LATERAL (
      -- Within a range find the last row of each timeline
      SELECT *
      FROM (
        SELECT su_range.*
             , ROW_NUMBER() OVER (PARTITION BY su_range.unit_type, su_range.unit_id ORDER BY su_range.valid_from DESC) = 1 AS last_in_range
        FROM public.statistical_unit AS su_range
        WHERE daterange(su_range.valid_from, su_range.valid_to, '[]') && daterange(range.curr_start,range.curr_stop,'[]')
          -- Entries already dead entries are not relevant.
          AND (su_range.death_date IS NULL OR range.curr_start <= su_range.death_date)
          -- Entries not yet born are not relevant.
          AND (su_range.birth_date IS NULL OR su_range.birth_date <= range.curr_stop)
          AND su_range.include_unit_in_reports
      ) AS range_units
      WHERE last_in_range
    ) AS su_curr ON true
    LEFT JOIN public.statistical_unit AS su_prev
      -- There may be a previous entry to compare with.
      ON su_prev.valid_from <= range.prev_stop AND range.prev_stop <= su_prev.valid_to
      AND su_prev.unit_type = su_curr.unit_type AND su_prev.unit_id = su_curr.unit_id
      AND su_prev.include_unit_in_reports
    WHERE range.resolution = 'year-month'
), year_and_month_with_unit_derived AS (
    SELECT basis.*
         --
         , track_changes AND NOT born AND not died AND prev_name                             IS DISTINCT FROM curr_name                             AS name_changed
         , track_changes AND NOT born AND not died AND prev_primary_activity_category_path   IS DISTINCT FROM curr_primary_activity_category_path   AS primary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_secondary_activity_category_path IS DISTINCT FROM curr_secondary_activity_category_path AS secondary_activity_category_changed
         , track_changes AND NOT born AND not died AND prev_sector_path                      IS DISTINCT FROM curr_sector_path                      AS sector_changed
         , track_changes AND NOT born AND not died AND prev_legal_form_id                    IS DISTINCT FROM curr_legal_form_id                    AS legal_form_changed
         , track_changes AND NOT born AND not died AND prev_physical_region_path             IS DISTINCT FROM curr_physical_region_path             AS physical_region_changed
         , track_changes AND NOT born AND not died AND prev_physical_country_id              IS DISTINCT FROM curr_physical_country_id              AS physical_country_changed
         , track_changes AND NOT born AND not died AND (
                 prev_physical_address_part1 IS DISTINCT FROM curr_physical_address_part1
              OR prev_physical_address_part2 IS DISTINCT FROM curr_physical_address_part2
              OR prev_physical_address_part3 IS DISTINCT FROM curr_physical_address_part3
         ) AS physical_address_changed
         , track_changes AND NOT born AND not died AND prev_unit_size_code IS DISTINCT FROM curr_unit_size_code AS unit_size_code_changed
         , track_changes AND NOT born AND not died AND prev_status_code IS DISTINCT FROM curr_status_code AS status_code_changed
         --
         -- TODO: Track the change in `stats` and put that into `stats_change` using `public.stats_change`.
         --, CASE WHEN track_changes THEN stop_stats - start_stats ELSE NULL END AS stats_change
         --
    FROM year_and_month_with_unit_basis AS basis
), year_with_unit_per_facet AS (
    SELECT source.resolution                       AS resolution
         , source.year                             AS year
         , NULL::INTEGER                           AS month
         , source.unit_type                        AS unit_type
         --
         , source.curr_primary_activity_category_path   AS primary_activity_category_path
         , source.curr_secondary_activity_category_path AS secondary_activity_category_path
         , source.curr_sector_path                      AS sector_path
         , source.curr_legal_form_id                    AS legal_form_id
         , source.curr_physical_region_path             AS physical_region_path
         , source.curr_physical_country_id              AS physical_country_id
         --
         , source.curr_unit_size_id                     AS unit_size_id
         , source.curr_status_id                        AS status_id
         --
         , COUNT(source.*) FILTER (WHERE NOT source.died) AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.name_changed)                        AS name_change_count
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_address_changed)            AS physical_address_change_count
         --
         , COUNT(source.*) FILTER (WHERE source.unit_size_code_changed)              AS unit_size_change_count
         , COUNT(source.*) FILTER (WHERE source.status_code_changed)                 AS status_change_count
         --
         , public.jsonb_stats_summary_merge_agg(source.stats_summary) AS stats_summary
    FROM year_with_unit_derived AS source
    GROUP BY resolution, year, unit_type
           , primary_activity_category_path
           , secondary_activity_category_path
           , sector_path
           , legal_form_id
           , physical_region_path
           , physical_country_id
           , unit_size_id
           , status_id
), year_and_month_with_unit_per_facet AS (
    SELECT source.resolution                       AS resolution
         , source.year                             AS year
         , source.month                            AS month
         , source.unit_type                        AS unit_type
         --
         , source.curr_primary_activity_category_path   AS primary_activity_category_path
         , source.curr_secondary_activity_category_path AS secondary_activity_category_path
         , source.curr_sector_path                      AS sector_path
         , source.curr_legal_form_id                    AS legal_form_id
         , source.curr_physical_region_path             AS physical_region_path
         , source.curr_physical_country_id              AS physical_country_id
         --
         , source.curr_unit_size_id                     AS unit_size_id
         , source.curr_status_id                        AS status_id
         --
         , COUNT(source.*) FILTER (WHERE NOT source.died) AS count
         --
         , COUNT(source.*) FILTER (WHERE source.born) AS births
         , COUNT(source.*) FILTER (WHERE source.died) AS deaths
         --
         , COUNT(source.*) FILTER (WHERE source.name_changed)                        AS name_change_count
         , COUNT(source.*) FILTER (WHERE source.primary_activity_category_changed)   AS primary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.secondary_activity_category_changed) AS secondary_activity_category_change_count
         , COUNT(source.*) FILTER (WHERE source.sector_changed)                      AS sector_change_count
         , COUNT(source.*) FILTER (WHERE source.legal_form_changed)                  AS legal_form_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_region_changed)             AS physical_region_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_country_changed)            AS physical_country_change_count
         , COUNT(source.*) FILTER (WHERE source.physical_address_changed)            AS physical_address_change_count
         --
         , COUNT(source.*) FILTER (WHERE source.unit_size_code_changed)         AS unit_size_change_count
         , COUNT(source.*) FILTER (WHERE source.status_code_changed)            AS status_change_count
         --
         , public.jsonb_stats_summary_merge_agg(source.stats_summary) AS stats_summary
    FROM year_and_month_with_unit_derived AS source
    GROUP BY resolution, year, month, unit_type
           , primary_activity_category_path
           , secondary_activity_category_path
           , sector_path
           , legal_form_id
           , physical_region_path
           , physical_country_id
           , unit_size_id
           , status_id
)
SELECT * FROM year_with_unit_per_facet
UNION ALL
SELECT * FROM year_and_month_with_unit_per_facet
;
SELECT pg_catalog.set_config('search_path', '', false);

END;
