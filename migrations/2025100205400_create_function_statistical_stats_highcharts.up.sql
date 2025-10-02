BEGIN;

-- ================================================
-- Function: public.statistical_stats_highcharts
-- Returns JSONB rows all dates for a given resolution and uniit_type
-- Number of Name changes, Address changes, change of activity category, births and deaths
--
--SELECT public.statistical_stats_highcharts( 'year'::history_resolution,'enterprise'::statistical_unit_type);
--SELECT public.statistical_stats_highcharts( 'year-month'::history_resolution,'legal_unit'::statistical_unit_type);
--SELECT public.statistical_stats_highcharts( 'year-month'::history_resolution,'establishment'::statistical_unit_type);
--Erik Oct 2025

-- ================================================



CREATE OR REPLACE FUNCTION public.statistical_stats_highcharts(
	p_resolution history_resolution,
	p_unit_type statistical_unit_type)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
AS $BODY$
DECLARE
    result jsonb;
BEGIN
    WITH base AS (
        SELECT
			  CASE 
            WHEN p_resolution = 'year' THEN
                make_timestamp(year, 1, 1, 0, 0, 0)
            ELSE
                make_timestamp(year, month, 1, 0, 0, 0)
        END AS ts,			
            name_change_count,
            primary_activity_category_change_count,
			births,
			deaths,
			physical_address_change_count,
			physical_region_change_count
			--'count'
			
        FROM public.statistical_history
        WHERE resolution = p_resolution
          AND unit_type = p_unit_type
        ORDER BY 1
    ),
    series_build AS (
        SELECT
            jsonb_build_object(
                'name', 'Name',
                'data', jsonb_agg(
                    jsonb_build_array(
                        extract(epoch FROM ts)::bigint * 1000,
                        name_change_count
                    )
                )
            ) AS series_item
        FROM base
		
        UNION ALL
        SELECT
            jsonb_build_object(
                'name', 'Primary activity',
                'data', jsonb_agg(
                    jsonb_build_array(
                        extract(epoch FROM ts)::bigint * 1000,
                        primary_activity_category_change_count
                    )
                )
            )
        FROM base
		
 		UNION ALL
        SELECT
            jsonb_build_object(
                'name', 'Births',
                'data', jsonb_agg(
                    jsonb_build_array(
                        extract(epoch FROM ts)::bigint * 1000,
                        births
                    )
                )
            )
        FROM base

UNION ALL
        SELECT
            jsonb_build_object(
                'name', 'Deaths',
                'data', jsonb_agg(
                    jsonb_build_array(
                        extract(epoch FROM ts)::bigint * 1000,
                        deaths
                    )
                )
            )
        FROM base

UNION ALL
        SELECT
            jsonb_build_object(
                'name', 'Physical address',
                'data', jsonb_agg(
                    jsonb_build_array(
                        extract(epoch FROM ts)::bigint * 1000,
                        physical_address_change_count
                    )
                )
            )
        FROM base

		
		
    )
    SELECT jsonb_build_object(
        'resolution', p_resolution,
        'unit_type', p_unit_type,
        'series', jsonb_agg(series_item)
    )
    INTO result
    FROM series_build;

    RETURN result;
END;
$BODY$;




END;
