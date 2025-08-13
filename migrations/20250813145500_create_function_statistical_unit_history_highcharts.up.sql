BEGIN;

-- ================================================
-- Function: statistical_unit_history statistical_unit_history_highcharts
-- Returns JSONB rows for a given unit_id and unit_type
-- 
--SELECT * FROM statistical_unit_history(25,'enterprise');
--SELECT * FROM statistical_unit_history_highcharts(25,'enterprise');
-- ================================================




CREATE OR REPLACE FUNCTION public.statistical_unit_history(
    p_unit_id int,
    p_unit_type statistical_unit_type
)
RETURNS SETOF jsonb
LANGUAGE plpgsql AS $statistical_unit_history$
DECLARE
    dynamic_stats_sql text;
    full_sql text;
BEGIN
    -- Build dynamic metrics selection from stat_definition
    SELECT string_agg(
        format(
            '(stats_summary->%L->>''sum'')::%s AS %I',
            sd.code,
            sd.type,
            COALESCE(sd.name, sd.code) -- safe alias
        ),
        ', '
    )
    INTO dynamic_stats_sql
    FROM public.stat_definition AS sd;

    -- Build final SQL — only metadata + metrics
    full_sql := format($SQL$
        SELECT to_jsonb(subq)
        FROM (
            SELECT 
                su.name,
                su.unit_id,
                su.valid_from,
                %1$s
            FROM public.statistical_unit AS su
            WHERE su.unit_id = %2$L
              AND su.unit_type = %3$L
        ) AS subq
    $SQL$,
    dynamic_stats_sql, -- %1$s
    p_unit_id,         -- %2$L
    p_unit_type        -- %3$L
    );

    -- Return JSON rows
    RETURN QUERY EXECUTE full_sql;
END;
$statistical_unit_history$;



-- ================================================
-- Function: statistical_unit_history_highcharts
-- Returns JSONB object ready for Highcharts
-- ================================================

CREATE OR REPLACE FUNCTION public.statistical_unit_history_highcharts(
    p_unit_id int,
    p_unit_type statistical_unit_type
)
RETURNS jsonb
LANGUAGE plpgsql AS $statistical_unit_history_highcharts$
DECLARE
    col text;
    keys text[];
    sql text;
    series jsonb;
    all_series jsonb := '[]'::jsonb;
    latest_name text;
BEGIN
    -- 1. Get the latest name from statistical_unit_history()
    SELECT j->>'name'
    INTO latest_name
    FROM statistical_unit_history(p_unit_id, p_unit_type) AS t(j)
    ORDER BY (j->>'valid_from')::date DESC
    LIMIT 1;

    -- 2. Get all metric keys except metadata
    SELECT array_agg(key ORDER BY key)
    INTO keys
    FROM (
        SELECT DISTINCT jsonb_object_keys(j) AS key
        FROM statistical_unit_history(p_unit_id, p_unit_type) AS t(j)
    ) AS sub
    WHERE key NOT IN ('name', 'unit_id', 'valid_from');

    -- 3. Loop through metrics and build series
    FOREACH col IN ARRAY keys
    LOOP
        sql := format($SQL$
            SELECT jsonb_build_object(
                'name', %1$L,
                'data', jsonb_agg(
                    jsonb_build_array(
                        extract(epoch from (j->>'valid_from')::date) * 1000,
                        NULLIF(
                            CASE
                                WHEN j->>%1$L ~ '^-?[0-9]+(\.[0-9]+)?$'
                                THEN j->>%1$L
                                ELSE NULL
                            END, ''
                        )::float
                    )
                    ORDER BY (j->>'valid_from')::date
                )
            )
            FROM statistical_unit_history(%2$L, %3$L) AS t(j)
        $SQL$,
        col,         -- %1$L
        p_unit_id,   -- %2$L
        p_unit_type  -- %3$L
        );

        EXECUTE sql INTO series;

        IF series IS NOT NULL THEN
            all_series := all_series || jsonb_build_array(series);
        END IF;
    END LOOP;

    -- 4. Return object with unit_id, latest name, and series array
    RETURN jsonb_build_object(
        'unit_id', p_unit_id,
        'unit_name', latest_name,
        'series', (
            SELECT jsonb_agg(s ORDER BY s->>'name')
            FROM jsonb_array_elements(all_series) AS s
        )
    );
END;
$statistical_unit_history_highcharts$;

END;
