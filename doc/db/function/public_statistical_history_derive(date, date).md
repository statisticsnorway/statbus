```sql
CREATE OR REPLACE FUNCTION public.statistical_history_derive(valid_after date DEFAULT '-infinity'::date, valid_to date DEFAULT 'infinity'::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_year int;
    v_month int;
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(valid_after=%, valid_to=%)', valid_after, valid_to;

    -- Get relevant periods using the get_statistical_history_periods function
    -- and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT year, month
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution, -- Get both year and year-month in the same table
        p_valid_after := statistical_history_derive.valid_after,
        p_valid_to := statistical_history_derive.valid_to
    );
        
    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING temp_periods tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;
      
    -- Insert new records for the affected periods
    INSERT INTO public.statistical_history
    SELECT shd.* 
    FROM public.statistical_history_def shd
    JOIN temp_periods p ON 
        shd.year = p.year AND 
        shd.month IS NOT DISTINCT FROM p.month
    ORDER BY shd.year, shd.month;
    
    -- Clean up
    DROP TABLE IF EXISTS temp_periods;
END;
$function$
```
