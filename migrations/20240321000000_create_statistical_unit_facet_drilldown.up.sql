BEGIN;

CREATE FUNCTION public.statistical_unit_facet_drilldown(
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
    -- Use a params intermediary to avoid conflicts
    -- between columns and parameters, leading to tautologies. i.e. 'sh.unit_type = unit_type' is always true.
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
        WHERE
            suf.valid_from <= param_valid_on AND param_valid_on <= suf.valid_to
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
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (   region_path IS NOT NULL
            AND r.path OPERATOR(public.@>) (region_path)
            )
        ORDER BY path
    ),
    available_region AS (
        SELECT r.path
             , r.label
             , r.code
             , r.name
        FROM public.region AS r
        WHERE
            (
                (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY r.path
    ), aggregated_region_counts AS (
        SELECT ar.path
             , ar.label
             , ar.code
             , ar.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.physical_region_path OPERATOR(public.<>) ar.path), false) AS has_children
        FROM available_region AS ar
        LEFT JOIN available_facet AS suf ON suf.physical_region_path OPERATOR(public.<@) ar.path
        GROUP BY ar.path
               , ar.label
               , ar.code
               , ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.active
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (     activity_category_path IS NOT NULL
              AND ac.path OPERATOR(public.@>) activity_category_path
            )
        ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path
             , ac.label
             , ac.code
             , ac.name
        FROM
            public.activity_category AS ac
        WHERE ac.active
           AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND
            (
                (activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY ac.path
    ),
    aggregated_activity_counts AS (
        SELECT aac.path
             , aac.label
             , aac.code
             , aac.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.primary_activity_category_path OPERATOR(public.<>) aac.path), false) AS has_children
        FROM
            available_activity_category AS aac
        LEFT JOIN available_facet AS suf ON suf.primary_activity_category_path OPERATOR(public.<@) aac.path
        GROUP BY aac.path
               , aac.label
               , aac.code
               , aac.name
    ),
    breadcrumb_sector AS (
        SELECT s.path
             , s.label
             , s.code
             , s.name
        FROM public.sector AS s
        WHERE
            (   sector_path IS NOT NULL
            AND s.path OPERATOR(public.@>) (sector_path)
            )
        ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
        FROM public.sector AS "as"
        WHERE
            (
                (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR
                (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
            )
        ORDER BY "as".path
    ), aggregated_sector_counts AS (
        SELECT "as".path
             , "as".label
             , "as".code
             , "as".name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , COALESCE(bool_or(true) FILTER (WHERE suf.sector_path OPERATOR(public.<>) "as".path), false) AS has_children
        FROM available_sector AS "as"
        LEFT JOIN available_facet AS suf ON suf.sector_path OPERATOR(public.<@) "as".path
        GROUP BY "as".path
               , "as".label
               , "as".code
               , "as".name
    ),
    breadcrumb_status AS (
        SELECT s.id
             , s.code
             , s.name
        FROM public.status AS s
        WHERE
            (   status_id IS NOT NULL
            AND s.id = status_id
            )
        ORDER BY s.id
    ),
    available_status AS (
        SELECT s.id
             , s.code
             , s.name
        FROM public.status AS s
        -- Every status is available, unless one is selected.
        WHERE status_id IS NULL
        ORDER BY s.id
    ),
    aggregated_status_counts AS (
        SELECT s.id
             , s.code
             , s.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_status AS s
        LEFT JOIN available_facet AS suf ON suf.status_id = s.id
        GROUP BY s.id
               , s.code
               , s.name
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        WHERE
            (   legal_form_id IS NOT NULL
            AND lf.id = legal_form_id
            )
        ORDER BY lf.id
    ),
    available_legal_form AS (
        SELECT lf.id
             , lf.code
             , lf.name
        FROM public.legal_form AS lf
        -- Every sector is available, unless one is selected.
        WHERE legal_form_id IS NULL
        ORDER BY lf.id
    ), aggregated_legal_form_counts AS (
        SELECT lf.id
             , lf.code
             , lf.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_legal_form AS lf
        LEFT JOIN available_facet AS suf ON suf.legal_form_id = lf.id
        GROUP BY lf.id
               , lf.code
               , lf.name
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        WHERE
            (   country_id IS NOT NULL
            AND pc.id = country_id
            )
        ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
        FROM public.country AS pc
        -- Every country is available, unless one is selected.
        WHERE country_id IS NULL
        ORDER BY pc.iso_2
    ), aggregated_physical_country_counts AS (
        SELECT pc.id
             , pc.iso_2
             , pc.name
             , COALESCE(SUM(suf.count), 0) AS count
             , public.jsonb_stats_summary_merge_agg(suf.stats_summary) AS stats_summary
             , false AS has_children
        FROM available_physical_country AS pc
        LEFT JOIN available_facet AS suf ON suf.physical_country_id = pc.id
        GROUP BY pc.id
               , pc.iso_2
               , pc.name
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
