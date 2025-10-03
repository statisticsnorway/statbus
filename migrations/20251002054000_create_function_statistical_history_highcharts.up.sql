BEGIN;

-- ================================================
-- Function: public.statistical_history_highcharts
-- Description:
--   Returns a JSONB object formatted for use with Highcharts.js, containing time series data
--   for statistical history metrics based on the specified resolution and unit type.
--
-- Parameters:
--   p_resolution: The time resolution ('year' or 'year-month').
--   p_unit_type: The statistical unit type ('enterprise', 'legal_unit', 'establishment').
--   p_year: Optional. An integer to filter the results to a single year, primarily for 'year-month' resolution.
--
-- Returns:
--   A JSONB object with the following structure:
--   {
--     "resolution": "year",
--     "unit_type": "enterprise",
--     "year": null, // or the integer year if specified and not stripped
--     "series": [
--       {
--         "code": "count", // The raw column name from statistical_history
--         "name": "Unit Count", // A human-readable name for the series
--         "data": [
--           [ 1262304000000, 1 ], // An array of [timestamp, value] pairs
--           [ 1293840000000, 1 ],
--           ...
--         ]
--       },
--       ...
--     ]
--   }
--
--   Note on `data` structure: The array of `[timestamp, value]` pairs is a compact format
--   standardly used by Highcharts to reduce payload size, as opposed to a more verbose
--   array of objects like `[{ "ts": ..., "value": ... }]`.
--   The timestamp is the UTC milliseconds since the epoch, as expected by JavaScript.
--
-- Example Usage:
--   SELECT jsonb_pretty(public.statistical_history_highcharts('year', 'enterprise'));
--   SELECT jsonb_pretty(public.statistical_history_highcharts('year-month', 'legal_unit', 2019));
--
-- Author: Erik, Oct 2025
-- ================================================



CREATE OR REPLACE FUNCTION public.statistical_history_highcharts(
	p_resolution public.history_resolution,
	p_unit_type public.statistical_unit_type,
    p_year INTEGER DEFAULT NULL,
    p_series_codes text[] DEFAULT NULL)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    -- VOLATILE is required because this function creates a temporary table.
    -- The performance impact is negligible as the temp table is very small,
    -- and this function is not intended to be used in a context where a STABLE
    -- function's caching behavior would provide a benefit. The use of a temp
    -- table is a deliberate choice to avoid code duplication for the series definitions.
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    result jsonb;
    v_filtered_codes text[];
    v_invalid_codes text[];
BEGIN
    -- Use a temporary table for series definitions to avoid code duplication.
    IF to_regclass('pg_temp.series_definition') IS NOT NULL THEN DROP TABLE series_definition; END IF;
    CREATE TEMP TABLE series_definition(priority int, is_default boolean, code text, name text) ON COMMIT DROP;
    INSERT INTO series_definition(priority, is_default, code, name)
    VALUES
        (10,  false, 'count',                                    'Unit Count'),
        (20,  true , 'births',                                   'Births'),
        (30,  true , 'deaths',                                   'Deaths'),
        (40,  false, 'name_change_count',                        'Name Changes'),
        (50,  true , 'primary_activity_category_change_count',   'Primary Activity Changes'),
        (60,  false, 'secondary_activity_category_change_count', 'Secondary Activity Changes'),
        (70,  false, 'sector_change_count',                      'Sector Changes'),
        (80,  false, 'legal_form_change_count',                  'Legal Form Changes'),
        (90,  true , 'physical_region_change_count',             'Region Changes'),
        (100, false, 'physical_country_change_count',            'Country Changes'),
        (110, false, 'physical_address_change_count',            'Physical Address Changes');

    -- Fail fast if any requested series codes are invalid.
    IF p_series_codes IS NOT NULL AND cardinality(p_series_codes) > 0 THEN
        SELECT array_agg(req_code)
        INTO v_invalid_codes
        FROM unnest(p_series_codes) AS t(req_code)
        WHERE NOT EXISTS (SELECT 1 FROM series_definition sd WHERE sd.code = t.req_code);

        IF v_invalid_codes IS NOT NULL AND cardinality(v_invalid_codes) > 0 THEN
            RAISE EXCEPTION 'Invalid series code(s) provided: %', array_to_string(v_invalid_codes, ', ');
        END IF;
    END IF;

    v_filtered_codes := CASE
        WHEN p_series_codes IS NULL OR cardinality(p_series_codes) = 0 THEN
            (SELECT array_agg(code) FROM series_definition WHERE is_default)
        ELSE
            p_series_codes
    END;

    WITH 
    base AS (
        -- Prepare base data, calculating the Javascript-compatible millisecond timestamp once.
        SELECT
            -- Highcharts expects UTC milliseconds since epoch.
            extract(epoch FROM
                CASE p_resolution
                    WHEN 'year' THEN make_timestamp(year, 1, 1, 0, 0, 0)
                    WHEN 'year-month' THEN make_timestamp(year, month, 1, 0, 0, 0)
                END
            )::bigint * 1000 AS ts_epoch_ms,
            "count", births, deaths, name_change_count,
            primary_activity_category_change_count, secondary_activity_category_change_count,
            sector_change_count, legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count
        FROM public.statistical_history
        WHERE resolution = p_resolution
          AND unit_type = p_unit_type
          AND (p_year IS NULL OR year = p_year)
    ),
    aggregated_data AS (
        -- Aggregate each metric into a JSONB array of [timestamp, value] pairs.
        SELECT
            jsonb_build_object(
                'count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, "count") ORDER BY ts_epoch_ms), '[]'::jsonb),
                'births', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, births) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'deaths', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, deaths) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'name_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, name_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'primary_activity_category_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, primary_activity_category_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'secondary_activity_category_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, secondary_activity_category_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'sector_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, sector_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'legal_form_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, legal_form_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'physical_region_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, physical_region_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'physical_country_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, physical_country_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb),
                'physical_address_change_count', COALESCE(jsonb_agg(jsonb_build_array(ts_epoch_ms, physical_address_change_count) ORDER BY ts_epoch_ms), '[]'::jsonb)
            ) as series_data_map
        FROM base
    )
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'resolution', p_resolution,
        'unit_type', p_unit_type,
        'year', p_year,
        'available_series', (
            SELECT jsonb_agg(jsonb_build_object('code', code, 'name', name, 'priority', priority) ORDER BY priority)
            FROM series_definition
            WHERE code <> ALL(v_filtered_codes)
        ),
        'filtered_series', to_jsonb(v_filtered_codes),
        'series', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'code', sd.code,
                    'name', sd.name,
                    'data', COALESCE(ad.series_data_map -> sd.code, '[]'::jsonb)
                ) ORDER BY sd.priority
            )
            FROM series_definition sd, aggregated_data ad
            WHERE sd.code = ANY(v_filtered_codes)
        )
    ))
    INTO result
    FROM aggregated_data;

    RETURN result;
END;
$BODY$;




END;
