```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_history_highcharts(p_unit_id integer, p_unit_type statistical_unit_type)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE PARALLEL SAFE
AS $function$
DECLARE
    col text;                 -- metric key name
    keys text[];              -- array of metric keys
    sql text;                 -- dynamic SQL for metric data
    series jsonb;             -- single metric's JSON
    all_series jsonb := '[]'::jsonb; -- accumulated series
    latest_name text;         -- latest unit name
    latest_valid_to text;     -- latest valid_to for unit name
    original_col text;        -- original column name without '*'
BEGIN
    -- 1. Get the latest name and valid_to from statistical_unit_history()
    SELECT j->>'name',
           j->>'valid_to'
    INTO latest_name, latest_valid_to
    FROM public.statistical_unit_history(p_unit_id, p_unit_type) AS t(j)
    ORDER BY (j->>'valid_from')::date DESC
    LIMIT 1;

    -- Append " *" if unit name's valid_to is 'infinity'
	--works but too much, and may not be all variables..?
    --IF latest_valid_to = 'infinity' THEN
    --    latest_name := latest_name || ' *';
    --END IF;

    -- 2. Get all metric keys except metadata fields
    SELECT array_agg(key ORDER BY key)
    INTO keys
    FROM (
        SELECT DISTINCT jsonb_object_keys(j) AS key
        FROM statistical_unit_history(p_unit_id, p_unit_type) AS t(j)
    ) AS sub
    WHERE key NOT IN ('name', 'unit_id', 'valid_from', 'valid_to');

    -- 3. Loop through metrics and build series
    FOREACH col IN ARRAY keys
    LOOP
        original_col := col; -- store original key for JSON lookup

        -- Check if this metric has any 'infinity' valid_to
        PERFORM 1
        FROM statistical_unit_history(p_unit_id, p_unit_type) AS t(j)
        WHERE j->>'valid_to' = 'infinity'
          AND j ? original_col; -- ensure key exists

        -- Append * if any infinity found
        IF FOUND THEN
            col := col || ' *';
        END IF;

        -- Build the JSON for this metric
        sql := format($SQL$
            SELECT jsonb_build_object(
                'name', %1$L,
                'data', jsonb_agg(
                    jsonb_build_array(
                        extract(epoch from (j->>'valid_from')::date) * 1000,
                        NULLIF(
                            CASE
                                WHEN j->>%2$L ~ '^-?[0-9]+(\.[0-9]+)?$'
                                THEN j->>%2$L
                                ELSE NULL
                            END, ''
                        )::float
                    )
                    ORDER BY (j->>'valid_from')::date
                )
            )
            FROM statistical_unit_history(%3$L, %4$L) AS t(j)
        $SQL$,
        col,               -- %1$L: name in chart (may have *)
        original_col,      -- %2$L: original key for lookup
        p_unit_id,         -- %3$L
        p_unit_type        -- %4$L
        );

        EXECUTE sql INTO series;

        IF series IS NOT NULL THEN
            all_series := all_series || jsonb_build_array(series);
        END IF;

        -- Reset col for next loop iteration
        col := original_col;
    END LOOP;

    -- 4. Return object with unit_id, adjusted latest name, and sorted series
    RETURN jsonb_build_object(
        'unit_id', p_unit_id,
        'unit_name', latest_name,
        'series', (
            SELECT jsonb_agg(s ORDER BY s->>'name')
            FROM jsonb_array_elements(all_series) AS s
        )
    );
END;
$function$
```
