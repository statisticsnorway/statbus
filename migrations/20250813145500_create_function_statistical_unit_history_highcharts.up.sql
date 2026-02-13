BEGIN;

-- ================================================
-- Function: statistical_unit_history_highcharts
-- Returns a single JSONB object formatted for Highcharts, with series sorted by priority.
--
-- This function is self-contained and queries `public.statistical_unit` directly.
-- It unpivots metrics from the `stats_summary` and `included_establishment_count` columns,
-- then re-aggregates them into the "wide" series format required by Highcharts.
--
-- Example: SELECT * FROM statistical_unit_history_highcharts(25,'enterprise');
-- ================================================
CREATE OR REPLACE FUNCTION public.statistical_unit_history_highcharts(
    p_unit_id integer,
    p_unit_type public.statistical_unit_type
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE PARALLEL SAFE
AS $statistical_unit_history_highcharts$
DECLARE
    latest_name text;
    series_data jsonb;
BEGIN
    WITH history_segments AS (
        -- 1. Select all historical segments for the given unit.
        SELECT
            name,
            valid_from,
            valid_to,
            stats_summary,
            included_establishment_count
        FROM public.statistical_unit
        WHERE unit_id = p_unit_id AND unit_type = p_unit_type
    ),
    long_format_metrics AS (
        -- 2. Unpivot all metrics into a long, normalized format.
        -- Unpivot from the JSONB stats_summary column
        SELECT
            s.valid_from,
            s.valid_to,
            j.key AS metric_code,
            (j.value->>'sum')::float AS metric_value
        FROM history_segments s,
             LATERAL jsonb_each(s.stats_summary) AS j
        WHERE j.value->>'sum' IS NOT NULL AND j.value->>'sum' ~ '^-?[0-9]+(\.[0-9]+)?$'

        UNION ALL

        -- Unpivot from the dedicated establishment count column
        SELECT
            s.valid_from,
            s.valid_to,
            'establishment_count' AS metric_code,
            s.included_establishment_count::float AS metric_value
        FROM history_segments s
        WHERE s.included_establishment_count IS NOT NULL
    ),
    metrics_with_defs AS (
        -- 3. Join with stat_definition to get display names and priorities.
        SELECT
            lf.valid_from,
            lf.valid_to,
            lf.metric_code,
            lf.metric_value,
            CASE
                WHEN lf.metric_code = 'establishment_count' THEN 'Establishments'
                ELSE COALESCE(sd.name, lf.metric_code)
            END AS display_name,
            CASE
                -- The 'establishment_count' metric is always sorted last.
                WHEN lf.metric_code = 'establishment_count' THEN 999
                -- For others, use defined priority or generate a stable one.
                ELSE COALESCE(sd.priority, 100 + row_number() OVER (PARTITION BY sd.priority IS NULL ORDER BY lf.metric_code))
            END AS priority
        FROM long_format_metrics lf
        LEFT JOIN public.stat_definition sd ON sd.code = lf.metric_code
        WHERE sd.enabled IS DISTINCT FROM false -- Exclude disabled stats, allow non-matches
    )
    SELECT
        -- 4a. Get the latest name of the unit for the chart title.
        (SELECT name FROM history_segments ORDER BY valid_from DESC LIMIT 1),

        -- 4b. Aggregate the long-format metrics into the final series structure.
        (
            SELECT jsonb_agg(series ORDER BY priority, display_name)
            FROM (
                SELECT
                    m.display_name,
                    m.priority,
                    jsonb_build_object(
                        'code', m.metric_code,
                        'name', m.display_name,
                        'is_current', bool_or(m.valid_to = 'infinity'),
                        'priority', m.priority,
                        'data', jsonb_agg(
                            jsonb_build_array(
                                extract(epoch from m.valid_from)::bigint * 1000,
                                m.metric_value
                            )
                            ORDER BY m.valid_from
                        )
                    ) AS series
                FROM metrics_with_defs AS m
                GROUP BY m.metric_code, m.display_name, m.priority
            ) AS final_series
        )
    INTO latest_name, series_data;

    -- 5. Return the final JSONB object, ready for Highcharts.
    RETURN jsonb_build_object(
        'unit_id', p_unit_id,
        'unit_type', p_unit_type,
        'unit_name', latest_name,
        'series', COALESCE(series_data, '[]'::jsonb)
    );
END;
$statistical_unit_history_highcharts$;

END;
