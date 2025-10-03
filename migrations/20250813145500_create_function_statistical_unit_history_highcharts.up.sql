BEGIN;

-- ================================================
-- Function: statistical_unit_history
-- Returns JSONB rows for a given unit_id and unit_type, including statistical variables.
-- The data is used as a source for statistical_unit_history_highcharts.
--
-- Example: SELECT * FROM statistical_unit_history(25,'enterprise');
-- ================================================
CREATE OR REPLACE FUNCTION public.statistical_unit_history(
	p_unit_id integer,
	p_unit_type public.statistical_unit_type)
    RETURNS SETOF jsonb
    LANGUAGE plpgsql
    STABLE PARALLEL SAFE
AS $statistical_unit_history$
DECLARE
    dynamic_stats_sql text;
    full_sql text;
BEGIN
    -- Build dynamic metrics selection from stat_definition, using clean names.
    SELECT string_agg(
        format(
            '(stats_summary->%L->>''sum'')::%s AS %I',
            sd.code,
            sd.type,
            sd.code -- Use stable code as the key
        ),
        ', '
    )
    INTO dynamic_stats_sql
    FROM public.stat_definition AS sd
    WHERE sd.archived = false; -- Filter out archived definitions

    -- Build final SQL to select metadata and all dynamic statistical variables.
    full_sql := format($SQL$
        SELECT to_jsonb(subq)
        FROM (
            SELECT
                su.name,
                su.unit_id,
                su.valid_from,
                su.valid_to,
                %1$s, -- Dynamic statistical variables
                su.included_establishment_count AS "establishment_count" -- Use a stable code for establishment count
            FROM public.statistical_unit AS su
            WHERE su.unit_id = %2$L
              AND su.unit_type = %3$L
        ) AS subq
    $SQL$,
    dynamic_stats_sql, -- %1$s
    p_unit_id,         -- %2$L
    p_unit_type        -- %3$L
    );

    -- Return JSON rows for each time segment of the unit's history.
    RETURN QUERY EXECUTE full_sql;
END;
$statistical_unit_history$;



-- ================================================
-- Function: statistical_unit_history_highcharts
-- Returns a single JSONB object formatted for Highcharts, with series sorted by priority.
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
    -- This function has been refactored for performance.
    -- The previous version called `statistical_unit_history` multiple times for each metric,
    -- leading to significant inefficiency.
    -- This version calls it only ONCE, materializes the results in the `history_data` CTE,
    -- and then performs all subsequent operations on that in-memory data.

    WITH history_data AS (
        -- 1. Materialize history data to avoid repeated function calls.
        SELECT j AS data
        FROM public.statistical_unit_history(p_unit_id, p_unit_type) AS t(j)
    )
    SELECT
        -- 2a. Get the latest name of the unit for the chart title.
        (SELECT data->>'name' FROM history_data ORDER BY (data->>'valid_from')::date DESC LIMIT 1),

        -- 2b. Build all series in a single, efficient query.
        (
            WITH metric_keys AS (
                -- Get all unique keys that represent statistical variables from the history.
                SELECT DISTINCT key
                FROM history_data,
                     LATERAL jsonb_object_keys(data) AS key
                WHERE key NOT IN ('name', 'unit_id', 'valid_from', 'valid_to')
            ),
            metrics AS (
                -- Join with stat_definition to get priority and display name for sorting and labeling series.
                SELECT
                    mk.key,
                    CASE
                        WHEN mk.key = 'establishment_count' THEN 'Establishments'
                        ELSE COALESCE(sd.name, mk.key)
                    END AS display_name,
                    CASE
                        -- The 'establishment_count' metric is always sorted last.
                        WHEN mk.key = 'establishment_count' THEN 999
                        -- For all other metrics, use the priority from stat_definition if available.
                        -- If not, assign a stable, sequential priority starting from 100.
                        ELSE COALESCE(sd.priority, 100 + row_number() OVER (PARTITION BY (sd.priority IS NULL) ORDER BY mk.key))
                    END AS priority,
                    -- Check if any record for this metric has an open-ended validity ('infinity').
                    EXISTS (
                        SELECT 1
                        FROM history_data
                        WHERE data->>'valid_to' = 'infinity' AND data ? mk.key
                    ) AS has_infinity
                FROM metric_keys AS mk
                LEFT JOIN public.stat_definition AS sd ON sd.code = mk.key
            )
            SELECT jsonb_agg(
                jsonb_build_object(
                    'code', m.key,
                    'name', m.display_name,
                    'is_current', m.has_infinity,
                    'priority', m.priority,
                    'data', (
                        -- Aggregate historical data points for this metric.
                        SELECT jsonb_agg(
                            jsonb_build_array(
                                extract(epoch from (data->>'valid_from')::date) * 1000,
                                (data->>m.key)::float
                            )
                            ORDER BY (data->>'valid_from')::date
                        )
                        FROM history_data
                        -- Only include valid, numeric data points.
                        WHERE data->>m.key IS NOT NULL AND data->>m.key ~ '^-?[0-9]+(\.[0-9]+)?$'
                    )
                )
                ORDER BY m.priority, m.key -- Sort the final series array by priority, then name.
            )
            FROM metrics m
            -- Ensure we only create series for metrics that have at least one valid data point.
            WHERE (
                SELECT count(*) > 0
                FROM history_data
                WHERE data->>m.key IS NOT NULL AND data->>m.key ~ '^-?[0-9]+(\.[0-9]+)?$'
            )
        )
    INTO latest_name, series_data;

    -- 3. Return the final JSONB object, ready for Highcharts.
    RETURN jsonb_build_object(
        'unit_id', p_unit_id,
        'unit_name', latest_name,
        'series', COALESCE(series_data, '[]'::jsonb)
    );
END;
$statistical_unit_history_highcharts$;

END;
