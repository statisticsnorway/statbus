```sql
CREATE OR REPLACE FUNCTION public.timesegments_years_refresh()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Create a temporary table with the new data from the definition view
    CREATE TEMPORARY TABLE temp_timesegments_years ON COMMIT DROP AS
    SELECT * FROM public.timesegments_years_def;

    -- Delete years that are in the main table but not in the new set
    DELETE FROM public.timesegments_years t
    WHERE NOT EXISTS (
        SELECT 1 FROM temp_timesegments_years tt
        WHERE tt.year = t.year
    );

    -- Insert new years that are in the new set but not in the main table
    INSERT INTO public.timesegments_years (year)
    SELECT tt.year
    FROM temp_timesegments_years tt
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments_years t
        WHERE t.year = tt.year
    );

    -- The temporary table is dropped automatically on commit, but we drop it
    -- explicitly to be safe in transactional testing environments.
    DROP TABLE temp_timesegments_years;
END;
$function$
```
