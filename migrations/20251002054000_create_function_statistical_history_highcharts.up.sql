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
    p_year INTEGER DEFAULT NULL)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
AS $BODY$
DECLARE
    result jsonb;
BEGIN
    WITH series_definition(priority, code, name) AS (
        VALUES
            (10, 'count'::text,                         'Unit Count'::text),
            (20, 'births',                              'Births'),
            (30, 'deaths',                              'Deaths'),
            (40, 'name_change_count',                   'Name Changes'),
            (50, 'primary_activity_category_change_count', 'Primary Activity Changes'),
            (60, 'secondary_activity_category_change_count', 'Secondary Activity Changes'),
            (70, 'sector_change_count',                 'Sector Changes'),
            (80, 'legal_form_change_count',             'Legal Form Changes'),
            (90, 'physical_region_change_count',        'Region Changes'),
            (100, 'physical_country_change_count',      'Country Changes'),
            (110, 'physical_address_change_count',      'Physical Address Changes')
    ),
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
        'series', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'code', sd.code,
                    'name', sd.name,
                    'data', COALESCE(ad.series_data_map -> sd.code, '[]'::jsonb)
                ) ORDER BY sd.priority
            )
            FROM series_definition sd, aggregated_data ad
        )
    ))
    INTO result
    FROM aggregated_data;

    RETURN result;
END;
$BODY$;




END;
