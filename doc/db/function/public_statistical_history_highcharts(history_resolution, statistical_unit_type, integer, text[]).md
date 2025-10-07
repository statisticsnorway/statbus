```sql
CREATE OR REPLACE FUNCTION public.statistical_history_highcharts(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL::integer, p_series_codes text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
```
