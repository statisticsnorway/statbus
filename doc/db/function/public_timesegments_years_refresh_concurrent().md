```sql
CREATE OR REPLACE PROCEDURE public.timesegments_years_refresh_concurrent()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- Insert missing years (idempotent - safe for concurrent calls)
    INSERT INTO public.timesegments_years (year)
    SELECT DISTINCT year FROM public.timesegments_years_def
    ON CONFLICT (year) DO NOTHING;

    -- Delete obsolete years (safe - multiple deletes have same effect)
    DELETE FROM public.timesegments_years t
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments_years_def d WHERE d.year = t.year
    );
END;
$procedure$
```
