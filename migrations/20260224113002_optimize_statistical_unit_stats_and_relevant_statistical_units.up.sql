-- Migration 20260224113002: optimize_statistical_unit_stats_and_relevant_statistical_units
--
-- Performance optimization: eliminate full-table CTE materialization in
-- relevant_statistical_units and statistical_unit_stats.
--
-- Before: valid_units CTE materializes ALL valid rows (100+ columns, width ~6KB each),
-- then scans every row calling statistical_unit_enterprise_id() per row = O(n).
--
-- After: Call enterprise_id() once, look up root by temporal PK index,
-- resolve related IDs from arrays, join back once for full rows.
-- statistical_unit_stats bypasses relevant_statistical_units entirely,
-- fetching only 6 needed columns.
BEGIN;

-- Optimized relevant_statistical_units: targeted PK lookups instead of full-table CTE
CREATE OR REPLACE FUNCTION public.relevant_statistical_units(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $relevant_statistical_units$
    -- Step 1: Find the enterprise row directly via temporal PK index
    WITH root_unit AS (
        SELECT su.unit_type, su.unit_id,
               su.related_legal_unit_ids,
               su.related_establishment_ids,
               su.external_idents
        FROM public.statistical_unit AS su
        WHERE su.unit_type = 'enterprise'
          AND su.unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
          AND su.valid_from <= $3 AND $3 < su.valid_until
    -- Step 2: Collect all relevant (unit_type, unit_id) pairs from arrays
    ), relevant_ids AS (
        SELECT 'enterprise'::statistical_unit_type AS unit_type, ru.unit_id FROM root_unit AS ru
        UNION ALL
        SELECT 'legal_unit'::statistical_unit_type, unnest(ru.related_legal_unit_ids) FROM root_unit AS ru
        UNION ALL
        SELECT 'establishment'::statistical_unit_type, unnest(ru.related_establishment_ids) FROM root_unit AS ru
    -- Step 3: Single join back to get full rows, ordered by external ident priority
    ), full_units AS (
        SELECT su.*
            , first_external.ident AS first_external_ident
        FROM relevant_ids AS ri
        JOIN public.statistical_unit AS su
          ON su.unit_type = ri.unit_type
         AND su.unit_id = ri.unit_id
         AND su.valid_from <= $3 AND $3 < su.valid_until
        LEFT JOIN LATERAL (
            SELECT eit.code, (su.external_idents->>eit.code)::text AS ident
            FROM public.external_ident_type AS eit
            ORDER BY eit.priority
            LIMIT 1
        ) first_external ON true
        ORDER BY su.unit_type, first_external_ident NULLS LAST, su.unit_id
    )
    SELECT unit_type
         , unit_id
         , valid_from
         , valid_to
         , valid_until
         , external_idents
         , name
         , birth_date
         , death_date
         , search
         , primary_activity_category_id
         , primary_activity_category_path
         , primary_activity_category_code
         , secondary_activity_category_id
         , secondary_activity_category_path
         , secondary_activity_category_code
         , activity_category_paths
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , data_source_ids
         , data_source_codes
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postcode
         , physical_postplace
         , physical_region_id
         , physical_region_path
         , physical_region_code
         , physical_country_id
         , physical_country_iso_2
         , physical_latitude
         , physical_longitude
         , physical_altitude
         --
         , domestic
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postcode
         , postal_postplace
         , postal_region_id
         , postal_region_path
         , postal_region_code
         , postal_country_id
         , postal_country_iso_2
         , postal_latitude
         , postal_longitude
         , postal_altitude
         --
         , web_address
         , email_address
         , phone_number
         , landline
         , mobile_number
         , fax_number
         --
         , unit_size_id
         , unit_size_code
         --
         , status_id
         , status_code
         , used_for_counting
         --
         , last_edit_comment
         , last_edit_by_user_id
         , last_edit_at
         --
         , has_legal_unit
         , related_establishment_ids
         , excluded_establishment_ids
         , included_establishment_ids
         , related_legal_unit_ids
         , excluded_legal_unit_ids
         , included_legal_unit_ids
         , related_enterprise_ids
         , excluded_enterprise_ids
         , included_enterprise_ids
         , stats
         , stats_summary
         , included_establishment_count
         , included_legal_unit_count
         , included_enterprise_count
         , tag_paths
         , daterange(valid_from, valid_until) AS valid_range
         , report_partition_seq
    FROM full_units;
$relevant_statistical_units$;

-- Optimized statistical_unit_stats: bypass relevant_statistical_units entirely,
-- fetching only the 6 columns needed instead of 100+.
CREATE OR REPLACE FUNCTION public.statistical_unit_stats(
    unit_type public.statistical_unit_type,
    unit_id INTEGER,
    valid_on DATE DEFAULT current_date
) RETURNS SETOF public.statistical_unit_stats LANGUAGE sql STABLE AS $statistical_unit_stats$
    WITH root_unit AS (
        SELECT su.unit_id,
               su.related_legal_unit_ids,
               su.related_establishment_ids
        FROM public.statistical_unit AS su
        WHERE su.unit_type = 'enterprise'
          AND su.unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
          AND su.valid_from <= $3 AND $3 < su.valid_until
    ), relevant_ids AS (
        SELECT 'enterprise'::statistical_unit_type AS unit_type, ru.unit_id FROM root_unit AS ru
        UNION ALL
        SELECT 'legal_unit'::statistical_unit_type, unnest(ru.related_legal_unit_ids) FROM root_unit AS ru
        UNION ALL
        SELECT 'establishment'::statistical_unit_type, unnest(ru.related_establishment_ids) FROM root_unit AS ru
    )
    SELECT su.unit_type, su.unit_id, su.valid_from, su.valid_to, su.stats, su.stats_summary
    FROM relevant_ids AS ri
    JOIN public.statistical_unit AS su
      ON su.unit_type = ri.unit_type
     AND su.unit_id = ri.unit_id
     AND su.valid_from <= $3 AND $3 < su.valid_until
    ORDER BY su.unit_type, su.unit_id;
$statistical_unit_stats$;

END;
