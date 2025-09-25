```sql
CREATE OR REPLACE FUNCTION public.statistical_history_derive(p_valid_from date DEFAULT '-infinity'::date, p_valid_until date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_period RECORD;
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Get relevant periods and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT *
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution, -- Get both year and year-month
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING temp_periods tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Loop through each period and insert the new data by calling the _def function.
    FOR v_period IN SELECT * FROM temp_periods
    LOOP
        INSERT INTO public.statistical_history
        SELECT * FROM public.statistical_history_def(v_period.resolution, v_period.year, v_period.month);
    END LOOP;

    -- Clean up
    DROP TABLE IF EXISTS temp_periods;
END;
$function$
```
