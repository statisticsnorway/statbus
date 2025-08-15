```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_history(p_unit_id integer, p_unit_type statistical_unit_type)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
```
