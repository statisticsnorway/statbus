-- Migration 20260215164911: fix_drilldown_partition_seq_filter
--
-- Both drilldown functions are SECURITY DEFINER (bypass RLS) and query
-- statistical_history_facet / statistical_unit_facet without filtering
-- partition_seq. This causes them to see both root and partition entries,
-- doubling all counts.
--
-- Fix: Add "AND partition_seq IS NULL" to the main CTE in each function.
BEGIN;

-- =====================================================================
-- statistical_history_drilldown: add partition_seq IS NULL filter
-- Based on 20240328000000_create_statistical_history_drilldown.up.sql
-- =====================================================================
CREATE OR REPLACE FUNCTION public.statistical_history_drilldown(
    unit_type public.statistical_unit_type DEFAULT 'enterprise',
    resolution public.history_resolution DEFAULT 'year',
    year INTEGER DEFAULT NULL,
    region_path public.ltree DEFAULT NULL,
    activity_category_path public.ltree DEFAULT NULL,
    sector_path public.ltree DEFAULT NULL,
    status_id INTEGER DEFAULT NULL,
    legal_form_id INTEGER DEFAULT NULL,
    country_id INTEGER DEFAULT NULL,
    year_min INTEGER DEFAULT NULL,
    year_max INTEGER DEFAULT NULL
)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.resolution = resolution' is always true.
    WITH params AS (
        SELECT
            unit_type AS param_unit_type,
            resolution AS param_resolution,
            year AS param_year,
            region_path AS param_region_path,
            activity_category_path AS param_activity_category_path,
            sector_path AS param_sector_path,
            legal_form_id AS param_legal_form_id,
            status_id AS param_status_id,
            country_id AS param_country_id
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    available_history AS (
        SELECT sh.*
        FROM public.statistical_history_facet AS sh
           , params
        WHERE sh.partition_seq IS NULL -- Only root entries (not partition computation entries)
          AND (param_unit_type IS NULL OR sh.unit_type = param_unit_type)
          AND (param_resolution IS NULL OR sh.resolution = param_resolution)
          AND (param_year IS NULL OR sh.year = param_year)
          AND (
              param_region_path IS NULL
              OR sh.physical_region_path IS NOT NULL AND sh.physical_region_path OPERATOR(public.<@) param_region_path
              )
          AND (
              param_activity_category_path IS NULL
              OR sh.primary_activity_category_path IS NOT NULL AND sh.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path
              )
          AND (
              param_sector_path IS NULL
              OR sh.sector_path IS NOT NULL AND sh.sector_path OPERATOR(public.<@) param_sector_path
              )
          AND (
              param_legal_form_id IS NULL
              OR sh.legal_form_id IS NOT NULL AND sh.legal_form_id = param_legal_form_id
              )
          AND (
              param_status_id IS NULL
              OR sh.status_id IS NOT NULL AND sh.status_id = param_status_id
              )
          AND (
              param_country_id IS NULL
              OR sh.physical_country_id IS NOT NULL AND sh.physical_country_id = param_country_id
              )
          AND (
              statistical_history_drilldown.year_min IS NULL
              OR sh.year IS NOT NULL AND sh.year >= statistical_history_drilldown.year_min
              )
          AND (
              statistical_history_drilldown.year_max IS NULL
              OR sh.year IS NOT NULL AND sh.year <= statistical_history_drilldown.year_max
              )
    ), available_history_stats AS (
        SELECT
            ah.year, ah.month
            -- Sum up all the demographic and change counts across the filtered facets
            , COALESCE(SUM(ah.exists_count), 0)::integer AS exists_count
            , COALESCE(SUM(ah.exists_change), 0)::integer AS exists_change
            , COALESCE(SUM(ah.exists_added_count), 0)::integer AS exists_added_count
            , COALESCE(SUM(ah.exists_removed_count), 0)::integer AS exists_removed_count
            , COALESCE(SUM(ah.countable_count), 0)::integer AS countable_count
            , COALESCE(SUM(ah.countable_change), 0)::integer AS countable_change
            , COALESCE(SUM(ah.countable_added_count), 0)::integer AS countable_added_count
            , COALESCE(SUM(ah.countable_removed_count), 0)::integer AS countable_removed_count
            , COALESCE(SUM(ah.births), 0)::integer AS births
            , COALESCE(SUM(ah.deaths), 0)::integer AS deaths
            , COALESCE(SUM(ah.name_change_count), 0)::integer AS name_change_count
            , COALESCE(SUM(ah.primary_activity_category_change_count), 0)::integer AS primary_activity_category_change_count
            , COALESCE(SUM(ah.secondary_activity_category_change_count), 0)::integer AS secondary_activity_category_change_count
            , COALESCE(SUM(ah.sector_change_count), 0)::integer AS sector_change_count
            , COALESCE(SUM(ah.legal_form_change_count), 0)::integer AS legal_form_change_count
            , COALESCE(SUM(ah.physical_region_change_count), 0)::integer AS physical_region_change_count
            , COALESCE(SUM(ah.physical_country_change_count), 0)::integer AS physical_country_change_count
            , COALESCE(SUM(ah.physical_address_change_count), 0)::integer AS physical_address_change_count
            , COALESCE(SUM(ah.unit_size_change_count), 0)::integer AS unit_size_change_count
            , COALESCE(SUM(ah.status_change_count), 0)::integer AS status_change_count
            , COALESCE(public.jsonb_stats_summary_merge_agg(ah.stats_summary), '{}'::jsonb) AS stats_summary
        FROM available_history AS ah
        GROUP BY ah.year, ah.month
        ORDER BY year ASC, month ASC NULLS FIRST
    ),
    breadcrumb_region AS (
        SELECT r.path, r.label, r.code, r.name
        FROM public.region AS r
        WHERE (region_path IS NOT NULL AND r.path OPERATOR(public.@>) (region_path))
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path, r.label, r.code, r.name
        FROM public.region AS r
        WHERE ((region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery))
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path, ar.label, ar.code, ar.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_history AS sh ON sh.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path, ar.label, ar.code, ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name
        FROM public.activity_category AS ac
        WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.@>) activity_category_path)
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name
        FROM public.activity_category AS ac
        WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND ((activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
             OR (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery))
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path, aac.label, aac.code, aac.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM available_activity_category AS aac
        LEFT JOIN available_history AS sh ON sh.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path, aac.label, aac.code, aac.name
        ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path, s.label, s.code, s.name
        FROM public.sector AS s
        WHERE (sector_path IS NOT NULL AND s.path OPERATOR(public.@>) (sector_path))
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path, "as".label, "as".code, "as".name
        FROM public.sector AS "as"
        WHERE ((sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery))
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path, "as".label, "as".code, "as".name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sh.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_history AS sh ON sh.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path, "as".label, "as".code, "as".name
       ORDER BY "as".path
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id, lf.code, lf.name
        FROM public.legal_form AS lf
        WHERE (legal_form_id IS NOT NULL AND lf.id = legal_form_id)
        ORDER BY lf.code
    ),
    available_legal_form AS (
        SELECT lf.id, lf.code, lf.name
        FROM public.legal_form AS lf
        WHERE legal_form_id IS NULL
        ORDER BY lf.code
    ), aggregated_legal_form_counts AS (
        SELECT lf.id, lf.code, lf.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_history AS sh ON sh.legal_form_id = lf.id
        GROUP BY lf.id, lf.code, lf.name
        ORDER BY lf.code
    ),
    breadcrumb_status AS (
        SELECT s.id, s.code, s.name
        FROM public.status AS s
        WHERE (status_id IS NOT NULL AND s.id = status_id)
        ORDER BY s.code
    ),
    available_status AS (
        SELECT s.id, s.code, s.name
        FROM public.status AS s
        WHERE status_id IS NULL
        ORDER BY s.code
    ), aggregated_status_counts AS (
        SELECT s.id, s.code, s.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_status AS s
        LEFT JOIN available_history AS sh ON sh.status_id = s.id
        GROUP BY s.id, s.code, s.name
        ORDER BY s.code
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name
        FROM public.country AS pc
        WHERE (country_id IS NOT NULL AND pc.id = country_id)
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name
        FROM public.country AS pc
        WHERE country_id IS NULL
        ORDER BY pc.iso_2
    ), aggregated_physical_country_counts AS (
        SELECT pc.id, pc.iso_2, pc.name
             , COALESCE(SUM(sh.countable_count), 0) AS count
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_history AS sh ON sh.physical_country_id = pc.id
        GROUP BY pc.id, pc.iso_2, pc.name
        ORDER BY pc.iso_2
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT jsonb_agg(to_jsonb(source.*)) FROM available_history_stats AS source),
          'breadcrumb',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_status AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_status_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter',jsonb_build_object(
            'type',param_resolution,
            'year',param_year,
            'unit_type',param_unit_type,
            'region_path',param_region_path,
            'activity_category_path',param_activity_category_path,
            'sector_path',param_sector_path,
            'legal_form_id',param_legal_form_id,
            'status_id',param_status_id,
            'country_id',param_country_id
          )
        )
    FROM params;
$$;

-- =====================================================================
-- statistical_unit_facet_drilldown: add partition_seq IS NULL filter
-- Based on 20240321000000_create_statistical_unit_facet_drilldown.up.sql
-- =====================================================================
CREATE OR REPLACE FUNCTION public.statistical_unit_facet_drilldown(
    unit_type public.statistical_unit_type DEFAULT 'enterprise',
    region_path public.ltree DEFAULT NULL,
    activity_category_path public.ltree DEFAULT NULL,
    sector_path public.ltree DEFAULT NULL,
    status_id INTEGER DEFAULT NULL,
    legal_form_id INTEGER DEFAULT NULL,
    country_id INTEGER DEFAULT NULL,
    valid_on date DEFAULT current_date
)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
    WITH params AS (
        SELECT unit_type AS param_unit_type
             , region_path AS param_region_path
             , activity_category_path AS param_activity_category_path
             , sector_path AS param_sector_path
             , status_id AS param_status_id
             , legal_form_id AS param_legal_form_id
             , country_id AS param_country_id
             , valid_on AS param_valid_on
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    available_facet AS (
        SELECT suf.physical_region_path
             , suf.primary_activity_category_path
             , suf.sector_path
             , suf.legal_form_id
             , suf.physical_country_id
             , suf.status_id
             , count
             , stats_summary
        FROM public.statistical_unit_facet AS suf
           , params
        WHERE suf.partition_seq IS NULL -- Only root entries (not partition computation entries)
            AND suf.valid_from <= param_valid_on AND param_valid_on < suf.valid_until
            AND (param_unit_type IS NULL OR suf.unit_type = param_unit_type)
            AND (
                param_region_path IS NULL
                OR suf.physical_region_path IS NOT NULL AND suf.physical_region_path OPERATOR(public.<@) param_region_path
            )
            AND (
                param_activity_category_path IS NULL
                OR suf.primary_activity_category_path IS NOT NULL AND suf.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path
            )
            AND (
                param_sector_path IS NULL
                OR suf.sector_path IS NOT NULL AND suf.sector_path OPERATOR(public.<@) param_sector_path
            )
            AND (
                param_status_id IS NULL
                OR suf.status_id IS NOT NULL AND suf.status_id = param_status_id
            )
            AND (
                param_legal_form_id IS NULL
                OR suf.legal_form_id IS NOT NULL AND suf.legal_form_id = param_legal_form_id
            )
            AND (
                param_country_id IS NULL
                OR suf.physical_country_id IS NOT NULL AND suf.physical_country_id = param_country_id
            )
    ), available_facet_stats AS (
        SELECT COALESCE(SUM(af.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(af.stats_summary) AS stats_summary
        FROM available_facet AS af
    ),
    breadcrumb_region AS (
        SELECT r.path, r.label, r.code, r.name
        FROM public.region AS r
        WHERE (region_path IS NOT NULL AND r.path OPERATOR(public.@>) (region_path))
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path, r.label, r.code, r.name
        FROM public.region AS r
        WHERE ((region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery))
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path, ar.label, ar.code, ar.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_facet AS suf ON suf.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path, ar.label, ar.code, ar.name
        ORDER BY ar.path
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name
        FROM public.activity_category AS ac
        WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.@>) activity_category_path)
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name
        FROM public.activity_category AS ac
        WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND ((activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
             OR (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery))
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path, aac.label, aac.code, aac.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM available_activity_category AS aac
        LEFT JOIN available_facet AS suf ON suf.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path, aac.label, aac.code, aac.name
        ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path, s.label, s.code, s.name
        FROM public.sector AS s
        WHERE (sector_path IS NOT NULL AND s.path OPERATOR(public.@>) (sector_path))
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path, "as".label, "as".code, "as".name
        FROM public.sector AS "as"
        WHERE ((sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery))
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path, "as".label, "as".code, "as".name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_facet AS suf ON suf.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path, "as".label, "as".code, "as".name
        ORDER BY "as".path
    ),
    breadcrumb_status AS (
        SELECT s.id, s.code, s.name
        FROM public.status AS s
        WHERE (status_id IS NOT NULL AND s.id = status_id)
        ORDER BY s.id
    ),
    available_status AS (
        SELECT s.id, s.code, s.name, s.priority
        FROM public.status AS s
        WHERE status_id IS NULL
        ORDER BY s.priority
    ),
    aggregated_status_counts AS (
        SELECT s.id, s.code, s.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_status AS s
        LEFT JOIN available_facet AS suf ON suf.status_id = s.id
        GROUP BY s.id, s.code, s.name, s.priority
        ORDER BY s.priority
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id, lf.code, lf.name
        FROM public.legal_form AS lf
        WHERE (legal_form_id IS NOT NULL AND lf.id = legal_form_id)
        ORDER BY lf.id
    ),
    available_legal_form AS (
        SELECT lf.id, lf.code, lf.name
        FROM public.legal_form AS lf
        WHERE legal_form_id IS NULL
        ORDER BY lf.name
    ), aggregated_legal_form_counts AS (
        SELECT lf.id, lf.code, lf.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_facet AS suf ON suf.legal_form_id = lf.id
        GROUP BY lf.id, lf.code, lf.name
        ORDER BY lf.name
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name
        FROM public.country AS pc
        WHERE (country_id IS NOT NULL AND pc.id = country_id)
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name
        FROM public.country AS pc
        WHERE country_id IS NULL
        ORDER BY pc.name
    ), aggregated_physical_country_counts AS (
        SELECT pc.id, pc.iso_2, pc.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_facet AS suf ON suf.physical_country_id = pc.id
        GROUP BY pc.id, pc.iso_2, pc.name
        ORDER BY pc.name
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT to_jsonb(source.*) FROM available_facet_stats AS source),
          'breadcrumb',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_status AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available',jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_status_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter',jsonb_build_object(
            'unit_type',param_unit_type,
            'region_path',param_region_path,
            'activity_category_path',param_activity_category_path,
            'sector_path',param_sector_path,
            'status_id',param_status_id,
            'legal_form_id',param_legal_form_id,
            'country_id',param_country_id,
            'valid_on',param_valid_on
          )
        )
    FROM params;
$$;

END;
